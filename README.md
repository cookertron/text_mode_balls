# Text Mode Balls

> **An advanced sprite animation engine running in standard MS-DOS VGA Text Mode (80x50), featuring sub-pixel positioning and hardware-accelerated compositing.**

![VGA Text Mode Demo](https://img.youtube.com/vi/CfdRuBoJMGQ/0.jpg)

## Overview

This project demonstrates that standard VGA Text Mode (`03h` / `12h`) is capable of far more than just displaying rigid grids of characters. By manipulating VGA hardware registers directly, we can turn the font memory into a dynamic sprite canvas.

The engine renders 16x16 pixel "balls" that:
- Move smoothly with **sub-pixel precision**.
- **Composite seamlessly** when overlapping (no "black box" artifacts).
- Run at a locked **60/70 FPS** on standard VGA hardware.

## Key Features

### 1. Sub-Pixel Precision
Text mode normally locks you to an 8x8 or 9x16 grid. We bypass this by:
- Using a pre-calculated **Lookup Table (LUT)** containing 64 variations of the ball sprite (shifted 0-7 pixels X and 0-7 pixels Y).
- Dynamically updating the **Font Memory (Plane 2)** for specific characters allocated to each ball.

### 2. Hardware Compositing (The "Secret Sauce")
Drawing overlapping sprites in text mode usually results in the top sprite's bounding box erasing the bottom sprite's pixels. We solved this using **VGA Write Mode 3**:
- We configure the VGA Graphics Controller to perform a logical `OR` operation directly in VRAM.
- When Ball A moves over Ball B, the engine switches to Mode 3, sets the "Paint Color" to White, and uses the new ball's pixels as a **Bit Mask**.
- Result: The new pixels are merged onto the existing background without destroying the underlying data.

### 3. Trail Clearing
To maintain performance, we track the screen offsets of every ball from the *previous* frame (`ClearOffsets`) and selectively erase them during the vertical retrace, ensuring no ghosting trails.

## Building the Project

This project is written in **x86 Assembly** for **Borland Turbo Assembler (TASM)**.

### Prerequisites
- MS-DOS Environment (e.g., DOSBox-X, 86Box, or real hardware).
- TASM 5.0 and TLINK.

### Build Steps
1. Clone the repository.
2. Run the build script:
   ```bat
   BUILD.BAT
   ```
3. Run the executable:
   ```bat
   BALLS.EXE
   ```

## File Structure

- **`BALLS.ASM`**: Main assembly source code. Contains the Render Loop, VGA Register Logic, and Physics.
- **`BALL_LUT.INC`**: Large lookup table containing all bit-shifted variations of the ball sprite.
- **`BUILD.BAT`**: Automated build script.

## Technical Details

- **Resolution**: 640x400 (Effective resolution of 80 cols * 8 pixels, 50 rows * 8 scanlines).
- **VGA Planes**:
  - **Plane 0/1**: Screen Character & Attribute RAM (`B800h`).
  - **Plane 2**: Font Bitmap Data (`A000h`).
- **Memory Model**: Small (16-bit real mode).

## Credits

- **Concept & Code**: @cookertron (Anthony)
- **Co-Pilot**: Antigravity (Google DeepMind Agentic AI)

---
*Created with ❤️ for MS-DOS.*



