# just-draw

`just-draw` is a small drawing app built with Zig + minifb.
It focuses on fast sketching with mouse input, and it also supports pressure-sensitive pen input through HID.

## Features

- Resizable drawing window (`1000x800` canvas)
- Circular brush with adjustable size
- Pressure-based brush growth when using a pen
- Draw mode, line mode, and rectangle mode
- Eraser mode
- Quick color switching
- Clear canvas shortcut

## Requirements

- Zig `0.16.0` or newer
- `hidapi`
- macOS (Cocoa + Metal)
- Linux (X11 + xkbcommon + hidapi-hidraw)

## Build

```bash
zig build
```

## Run

```bash
zig build run
```

Or run the installed binary:

```bash
./zig-out/bin/just_draw
```

## Controls

### Mouse

| Input | Action |
|---|---|
| Left click + drag | Draw |
| Right click + drag | Erase |
| Shift + left click | Line mode |
| Cmd/Super + left click | Rectangle mode |

### Keyboard

| Key | Action |
|---|---|
| `=` (same key as `+`) | Increase brush size |
| `-` | Decrease brush size |
| `0` | White |
| `1` | Red |
| `2` | Green |
| `3` | Blue |
| `4` | Yellow |
| `Backspace` | Clear canvas |

### Pen / Tablet

- Pen pressure increases brush size.
- Pen tip draws.
- Barrel buttons can adjust brush size.
- Double-tap barrel button 1 toggles eraser mode.

## Current limitations

- No save/export
- No undo/redo
- No layers

## License

MIT
