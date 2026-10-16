package transport

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"

	"github.com/Timo-In/code-preview.nvim/internal/diff"
	"github.com/neovim/go-client/nvim"
)

// Client wraps the Neovim msgpack RPC connection
type Client struct {
	nvimClient   *nvim.Nvim
	socketPath   string
	disconnected chan error
	mu           sync.Mutex
}

type UpdatePayload struct {
	WorktreeRoot string        `json:"worktree_root"`
	Path         string        `json:"path"`
	Lines        []string      `json:"lines"`
	Changes      []diff.Change `json:"changes"`
	TargetLine   int           `json:"target_line"`
	Revision     uint64        `json:"revision"`
}

func Connect(socketPath string) (*Client, error) {
	c, err := nvim.Dial(socketPath, nvim.DialServe(false))
	if err != nil {
		return nil, fmt.Errorf("failed to dial neovim socket at %s: %w", socketPath, err)
	}
	client := &Client{
		nvimClient:   c,
		socketPath:   socketPath,
		disconnected: make(chan error, 1),
	}
	go func() {
		client.disconnected <- c.Serve()
		close(client.disconnected)
	}()
	return client, nil
}

// Disconnected reports when the Neovim RPC connection stops serving.
func (c *Client) Disconnected() <-chan error {
	return c.disconnected
}

func (c *Client) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.nvimClient != nil {
		return c.nvimClient.Close()
	}
	return nil
}

// SendInPlaceUpdate invokes Lua in-place updater in Neovim
func (c *Client) SendInPlaceUpdate(payload UpdatePayload) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	luaCode := fmt.Sprintf(`
		local ok, mod = pcall(require, "code-preview.in_place")
		if ok and mod.on_diff_update then
			mod.on_diff_update(%q)
		end
	`, string(data))

	var result interface{}
	if err := c.nvimClient.ExecLua(luaCode, &result); err != nil {
		log.Printf("[rpc] ExecLua error: %v", err)
		return err
	}
	return nil
}
