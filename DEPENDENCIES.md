# Shift K.O. Pure Data Dependencies

This project uses Pure Data patches plus a small set of externals.

## Required

- Pure Data `0.56+` (tested on macOS arm64)
- Deken package: `else`

Used ELSE objects include:

- `else/eq~`
- `else/plate.rev~`
- `else/pitch.shift~`
- `else/white~`
- `else/pink~`
- `else/brown~`
- `else/lorenz~`

## Install (recommended)

Run:

```bash
./setup-pd.sh
```

Then in Pure Data:

1. Open `Help -> Find externals`
2. Search for `else`
3. Install the package and restart Pd

## Verify

After restarting Pd, open `shiftko-main.pd`.

If you still see `... couldn't create` for `else/...` objects, check:

- Pd path includes `~/Documents/Pd/externals`
- `else` exists under that folder
- `shiftko-main.pd` contains `declare -lib else`
