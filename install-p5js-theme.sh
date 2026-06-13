#!/bin/bash
# ============================================
# p5.js Lime Green Standard Theme Installer
# Agent-agnostic - works with Claude, Cursor, or any AI coding assistant
# ============================================

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Installing p5.js Lime Green Standard Theme...${NC}"

# Create .cursor/rules directory if it doesn't exist
mkdir -p .cursor/rules

# Write the MDC file
cat > .cursor/rules/p5js-theme-lime-standard.mdc << 'THEME_EOF'
---
alwaysApply: false
description: p5.js Theme System - Lime Green Standard. Clean, scientific theme for data visualization.
globs: ["**/*.js", "**/*.html", "**/p5*.js", "**/sketch*.js"]
---

# p5.js Lime Green Standard Theme

## Quick Reference

| Mode | Background | Text | Chart 1 | Chart 2 |
|------|------------|------|---------|---------|
| Light | #FFFFFF | #444444 | #A3D739 | #D4A539 |
| Dark | #555555 | #B8B8B8 | #A3D739 | #D439B8 |

## JavaScript Theme Object

```javascript
const themes = {
    light: {
        background: [255, 255, 255],
        foreground: [68, 68, 68],
        primary: [163, 215, 57],
        chart1: [163, 215, 57],
        chart2: [212, 165, 57]
    },
    dark: {
        background: [85, 85, 85],
        foreground: [184, 184, 184],
        primary: [163, 215, 57],
        chart1: [163, 215, 57],
        chart2: [212, 57, 184]
    }
};

let isDark = false;
let bg, text, c1, c2;

function updateColors() {
    const t = isDark ? themes.dark : themes.light;
    bg = color(...t.background);
    text = color(...t.foreground);
    c1 = color(...t.chart1);
    c2 = color(...t.chart2);
}
```

## CSS Variables

```css
:root {
    --bg-light: #FFFFFF;
    --fg-light: #444444;
    --primary: #A3D739;
    --chart-1-light: #A3D739;
    --chart-2-light: #D4A539;

    --bg-dark: #555555;
    --fg-dark: #B8B8B8;
    --chart-1-dark: #A3D739;
    --chart-2-dark: #D439B8;
}
```

## Complete HTML Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>p5.js Visualization</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/p5.js/1.7.0/p5.min.js"></script>
    <style>
        :root {
            --bg-light: #FFFFFF; --fg-light: #444444;
            --primary: #A3D739; --chart-2-light: #D4A539;
            --bg-dark: #555555; --fg-dark: #B8B8B8;
            --chart-2-dark: #D439B8;
        }
        body {
            margin: 0; padding: 20px;
            font-family: system-ui, sans-serif;
            background: var(--bg-light); color: var(--fg-light);
            display: flex; flex-direction: column; align-items: center;
            min-height: 100vh; transition: all 0.3s ease;
        }
        body.dark-theme { background: var(--bg-dark); color: var(--fg-dark); }
        #canvas-container {
            border: 2px solid var(--primary);
            border-radius: 10px; overflow: hidden;
            box-shadow: 0 10px 40px rgba(0,0,0,0.15);
        }
        .theme-toggle {
            position: fixed; top: 20px; right: 20px;
            background: var(--primary); color: white;
            border: none; border-radius: 50px;
            padding: 10px 20px; cursor: pointer; font-weight: 600;
        }
    </style>
</head>
<body>
    <button class="theme-toggle" onclick="toggleTheme()">Toggle Theme</button>
    <h1>Visualization Title</h1>
    <div id="canvas-container"></div>
    <script>
        let isDark = false;
        const themes = {
            light: { background: [255,255,255], foreground: [68,68,68], chart1: [163,215,57], chart2: [212,165,57] },
            dark: { background: [85,85,85], foreground: [184,184,184], chart1: [163,215,57], chart2: [212,57,184] }
        };
        let bg, text, c1, c2;

        function updateColors() {
            const t = isDark ? themes.dark : themes.light;
            bg = color(...t.background);
            text = color(...t.foreground);
            c1 = color(...t.chart1);
            c2 = color(...t.chart2);
        }

        function toggleTheme() {
            isDark = !isDark;
            document.body.classList.toggle('dark-theme', isDark);
            updateColors();
        }

        function setup() {
            let canvas = createCanvas(800, 500);
            canvas.parent('canvas-container');
            updateColors();
        }

        function draw() {
            background(bg);
            fill(c1); circle(width/3, height/2, 100);
            fill(c2); circle(width*2/3, height/2, 100);
            fill(text); textAlign(CENTER); textSize(14);
            text('Chart 1', width/3, height/2 + 80);
            text('Chart 2', width*2/3, height/2 + 80);
        }
    </script>
</body>
</html>
```

## Usage

- **chart1** (lime green #A3D739): Primary data, sine waves, first series
- **chart2** (golden/magenta): Secondary data, cosine waves, comparison
- **Primary stays consistent** across light/dark modes
- **Chart 2 adapts** for visibility on each background
THEME_EOF

echo -e "${GREEN}Theme installed to .cursor/rules/p5js-theme-lime-standard.mdc${NC}"
echo ""
echo "Usage: Tell any AI assistant to 'use the p5.js lime green theme'"
echo "Or reference: .cursor/rules/p5js-theme-lime-standard.mdc"
