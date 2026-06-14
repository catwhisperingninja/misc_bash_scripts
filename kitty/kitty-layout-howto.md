# kitty — window layouts that actually work

The single most common reason kitty "layouts won't work": people expect
tmux-style arbitrary splits but never enable the **`splits`** layout, and they
create new panes without telling kitty *where* to put them.

## The two things you must do

1. **Enable the `splits` layout** in `kitty.conf`. The first entry in
   `enabled_layouts` is the default for new tabs:

   ```
   enabled_layouts splits:split_axis=horizontal,stack,tall,fat,grid
   ```

   Only have **one** `enabled_layouts` line — a second one silently overrides
   the first (a classic foot-gun).

2. **Split with an explicit direction** using `launch --location`:

   ```
   map kitty_mod+enter  launch --location=hsplit --cwd=current   # split below
   map kitty_mod+\      launch --location=vsplit --cwd=current   # split right
   ```

   A plain `new_window` in the `splits` layout goes wherever kitty decides;
   `--location=hsplit|vsplit` is what gives you control.

## Built-in layouts (what each does)

| Layout   | Behaviour                                              |
|----------|-------------------------------------------------------|
| `splits` | Arbitrary tmux-style splits (use this)                |
| `stack`  | One pane fullscreen — your "zoom"                     |
| `tall`   | One big pane left, the rest stacked right             |
| `fat`    | One big pane top, the rest along the bottom           |
| `grid`   | Even NxN grid                                          |

`kitty_mod` defaults to `ctrl+shift`.

## Keys (from the shipped kitty.conf)

- `ctrl+shift+enter` split below · `ctrl+shift+\` split right
- `ctrl+shift+arrows` move focus · `ctrl+shift+shift+arrows` move pane
- `ctrl+shift+r` resize mode · `ctrl+shift+z` zoom (stack) toggle
- `ctrl+shift+l` next layout · `ctrl+shift+/` rotate splits

## Startup layout (saved sessions)

`kitty.conf` points at a session file:

```
startup_session session.conf
```

`session.conf` defines tabs + panes opened on launch. In a session file you
must set `layout splits` before the `launch --location` lines, and the first
`launch` is the root pane. See the shipped `session.conf`.

Launch a one-off layout without changing config:

```
kitty --session ~/.config/kitty/session.conf
```

## Install

```
mkdir -p ~/.config/kitty
cp kitty.conf session.conf ~/.config/kitty/
# reload in a running kitty: ctrl+shift+f5  (or just relaunch)
```

> "window layout" can also mean the **OS window** size/position, not panes.
> That's `remember_window_size`, `initial_window_width/height`, and (macOS)
> `hide_window_decorations` — also set in `kitty.conf`.
