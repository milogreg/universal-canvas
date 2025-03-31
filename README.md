This is the repo for the Universal Canvas website, hosted at [swag.garden/canvas](https://swag.garden/canvas).

A description of the Universal Canvas can be found on the site.

# Building

First, ensure you have zig 0.14.0 installed. You can find it at [ziglang.org/download](https://ziglang.org/download/).

To build, run `zig build --Doptimize=ReleaseFast` in the root directory of this repo.

After building, the generated site can be found in `zig-out/bin`.

### Alternate build modes

If you wish to enable safety checks, run `zig build --Doptimize=ReleaseSafe` instead. This will result in a noticeable drop in performance, so only use this during development.

Building with `zig build --Doptimize=ReleaseSmall` will result in a ~10-20x smaller WASM file, but also hurts the performance a fair bit.

# Project structure

Zig files live in the `src` directory. You can see how these files are used in `build.zig`.

Static site files live in the `static` directory. Everything in `static` is directly copied into the generated site.

Right now the code isn't structured or documented very well, so you may have to wade through some garbage in order to find out how things work. If some code seems pointless or needlessly convoluted, it very well may be.