# Contributing to Deposit OS

Thanks for your interest in helping build Deposit OS — a Linux distribution
assembled **from the kernel up** (our own kernel + a minimal, apt-compatible
userspace).

## Ways to contribute

- **Report bugs / request features** using the issue templates.
- **Improve packaging**: the `.mlpds` format and the `aqa` installer live in
  `tools/` and `tools/mlpds-installer/`.
- **Kernel / hardware enablement**: kernel config fragments live in
  `build/kernel-fragments/`; build logic in `build/build-kernel.sh`.
- **Userspace / desktop**: rootfs assembly is in `build/build-rootfs.sh` and
  tunables in `build/config.sh`.
- **Tooling**: the quick menu, Turbo FX, file manager and AV wrapper are
  Python/GTK3 scripts under `tools/`.

## Development workflow

1. Fork and clone the repo.
2. Most heavy lifting (kernel compile, rootfs debootstrap, live boot + screenshots)
   runs in **GitHub Actions** — just open a PR and the CI will build and boot the OS,
   embedding screenshots in the run Summary.
3. To build locally:
   ```bash
   bash build/build-kernel.sh        # compiles the kernel into build/output/kernel
   bash build/build-rootfs.sh        # debootstraps the userspace into build/output/rootfs
   bash ci/make-disk.sh build/output/rootfs build/output/kernel build/output/deposit-disk.img 4096
   bash ci/make-iso.sh  build/output/rootfs build/output/kernel build/output/deposit-os.iso
   ```
4. Keep commits focused and reference the issue they address.

## Coding conventions

- Shell scripts: `bash -n` clean, use `set -euo pipefail` where reasonable.
- Python/GTK tools: run `python3 -m py_compile`.
- Do **not** add forced bloatware or restrictive init systems — Deposit OS stays
  lean and systemd-based by deliberate choice.

## License

By contributing, you agree your contributions are licensed under the
[GPL-3.0](LICENSE) license, the same as the project.
