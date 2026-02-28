# just-draw

A simple drawing app I made with Zig and minifb. Nothing fancy, just lets you draw stuff on a canvas. No save feature, no layers, no undo - you draw, you see it, that's it.

## What It Does

Opens a window where you can draw with your mouse. The brush is a circle, and you can change its size. You can also draw lines and rectangles if you hold modifier keys.

## Requirements

- Zig 0.16+ (yeah it's a dev version, whatever)
- macOS (uses Cocoa/Metal stuff, so no Linux or Windows for now)

## Building

```
zig build
```

This compiles minifb from source and links it with the Zig code.

## Running

```
zig build run
```

Or after building:

```
./zig-out/bin/just_draw
```

## Usage

### Drawing

| Action | What It Does |
|--------|--------------|
| Left click + drag | Draw with current color |
| Right click + drag | Erase (draws background color) |
| Shift + left click + drag | Draw a straight line |
| Cmd + left click + drag | Draw a rectangle |

### Brush Size

| Key | Action |
|-----|--------|
| `+` | Increase brush size |
| `-` | Decrease brush size |

### Colors

| Key | Color |
|-----|-------|
| `0` | White |
| `1` | Red |
| `2` | Green |
| `3` | Blue |
| `4` | Yellow |

### Other

| Key | Action |
|-----|--------|
| Backspace | Clear the whole canvas |

## Notes

- There's no save/export. If you want to keep your drawing, take a screenshot.
- There's no undo. If you mess up, you mess up (I will implement this later).
- The canvas background is dark gray.
- Closing the window just closes it, nothing is saved anywhere.

### Contributions

Contributions are welcome

### Licence

MIT
