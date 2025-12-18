# Theme Swapping (Option A: Scoped CSS Variables)

This project maps Tailwind colors to CSS variables in `tailwind.config.ts` like:

- background → `hsl(var(--background))`
- primary → `hsl(var(--primary))`

Therefore, theme tokens must be HSL numeric triples (e.g., `60 100% 70%`), not
`hsl()` or OKLCH directly.

## 1) How this strategy works

- The default theme lives in `src/index.css` under `:root` (HSL triples).
- A new theme is defined as a scoped override using a data attribute:
  - Selector: `[data-theme="cmfvv5"]` and `.dark[data-theme="cmfvv5"]`
  - Location: `src/index.css` (look for `[id: theme-cmfvv5]`)
- Swap the theme by toggling `data-theme` on the `<html>` element (or a
  top-level container).
- Because Tailwind reads `hsl(var(--token))`, all utilities like
  `bg-background`, `text-foreground`, and `border` continue to work
  automatically with the new theme values.

## 2) Enable/disable the theme

HTML:

```html
<!-- Enable new theme -->
<html data-theme="cmfvv5">
	...
</html>

<!-- Enable dark variant of new theme -->
<html class="dark" data-theme="cmfvv5">
	...
</html>

<!-- Revert to default theme -->
<html>
	...
</html>
```

JavaScript/React:

```ts
// Enable
document.documentElement.setAttribute("data-theme", "cmfvv5");

// Enable dark variant too (if you use dark mode)
document.documentElement.classList.add("dark");

// Disable / revert to default
document.documentElement.removeAttribute("data-theme");
```

## 3) Editing theme values

- Open `src/index.css` and edit the `[data-theme="cmfvv5"]` block.
- Replace each placeholder with your desired HSL triple.
- Example values:
  - Pure black (opaque): `0 0% 0%`
  - Pure white (opaque): `0 0% 100%`
  - Yellow example: `60 100% 50%`

### “Black = rgba(0,0,0,0)” (fully transparent black)

- For elements in markup, you can use either:
  - Tailwind utility: `bg-black/0` (0% opacity), `bg-black/50` (50%), etc.
  - Inline style: `style="background-color: rgba(0,0,0,0);"`
- Theme tokens here are HSL triples (no alpha). If you need a variable with
  alpha, create a separate CSS rule using `rgba()` or use Tailwind’s opacity
  modifiers on utilities.

### Using an arbitrary hex color (e.g., #2518FE) with opacity

```html
<div class="bg-[#2518FE]/50">...</div>
```

- Swap `/50` for the desired opacity: `/40`, `/60`, etc.
- You can also experiment with blend modes: `mix-blend-overlay`,
  `mix-blend-multiply`, `mix-blend-hard-light`.

## 4) Converting OKLCH → HSL (for this project)

Your external theme is in OKLCH. Convert to HSL numeric triples and paste into
the theme block.

Options:

- Online converters (Culori, Color.js visualizers)
- Node with Culori:

```bash
npm i -D culori
node -e "const { converter } = require('culori'); const toHsl=converter('hsl'); const v=toHsl({mode:'oklch', l:0.7686, c:0.1647, h:70.0804}); console.log(v)"
```

This prints something like `{ h: 70.08, s: 100, l: 76.86 }` → use
`70.08 100% 76.86%`.

## 5) Tweaking overlays and filters (example)

For an overlay wash independent of the theme, use utilities right in JSX/CSS:

```tsx
<div className="absolute inset-0 bg-[#2518FE]/50 mix-blend-hard-light pointer-events-none" />
```

To make it more/less visible, change `/50` to `/40` or `/60`, or try
`mix-blend-overlay`, `mix-blend-multiply`, etc.

## 6) Rollback strategy

- To revert to the original look, remove `data-theme` from `<html>`.
- To fully remove the new theme, delete the `[data-theme="cmfvv5"]` blocks from
  `src/index.css`.
- No Tailwind config changes are required for this approach.

## 7) Quick checklist

- Toggle: `<html data-theme="cmfvv5">` (and optionally `class="dark"`).
- Edit: `src/index.css` → `[id: theme-cmfvv5]` HSL triples.
- Transparent black in HTML: `bg-black/0` or
  `style="background-color: rgba(0,0,0,0)"`.
