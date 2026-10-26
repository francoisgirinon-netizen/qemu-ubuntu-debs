# qemu-ubuntu-debs

`.deb` packages of the latest upstream [QEMU](https://www.qemu.org) aarch64 system
emulator for Ubuntu LTS releases that ship an older one.

| Ubuntu | Distro QEMU | Packages here |
|---|---|---|
| 22.04 | 6.2 | yes |
| 24.04 | 8.2.2 | yes |
| 26.04 | 10.2 | not needed |

## Why

Ubuntu 24.04 stays on QEMU 8.2.2, which misses upstream fix
[9d8d5a5b](https://gitlab.com/qemu-project/qemu/-/commit/9d8d5a5b) ("tcg: Fix iteration
step in 32-bit gvec operation"). On x86 hosts without AVX (for example VMs with a generic
"Common KVM processor" CPU model), aarch64 compare-with-zero instructions such as
`cmlt v.2s, v.2s, #0` then write only every other 32-bit lane, and the other lanes keep
stale register contents. Code vectorised by the compiler silently computes wrong values.
The Canonical server-backports PPA (QEMU 9.0.2) has the same bug.

## Package

- Name: `qemu-upstream-aarch64`, version `<qemu>-1~ubuntu<release>`.
- Unmodified upstream source from download.qemu.org, built with
  `--target-list=aarch64-softmmu --enable-virtfs`.
- Installed in `/opt/qemu-<version>`, with `qemu-system-aarch64` linked in `/usr/local/bin`,
  which comes before `/usr/bin` in the default `PATH`. The distribution QEMU packages are not
  replaced; remove this package to go back to them.

## Releases

A workflow checks download.qemu.org every day and publishes a release `qemu-<version>`
when a new stable version is out. It can also be run by hand for a given version
(Actions > Build QEMU .deb > Run workflow). Each release has one `.deb` per Ubuntu release and
a `SHA256SUMS` file.

## Install

```bash
curl -LO https://github.com/francoisgirinon-netizen/qemu-ubuntu-debs/releases/download/qemu-11.1.2/qemu-upstream-aarch64_11.1.2-1~ubuntu24.04_amd64.deb
sudo apt install ./qemu-upstream-aarch64_11.1.2-1~ubuntu24.04_amd64.deb
qemu-system-aarch64 --version
```

With Ansible:

```yaml
- name: Download QEMU {{ qemu_version }}
  ansible.builtin.get_url:
    url: "https://github.com/francoisgirinon-netizen/qemu-ubuntu-debs/releases/download/qemu-{{ qemu_version }}/qemu-upstream-aarch64_{{ qemu_version }}-1~ubuntu{{ ansible_distribution_version }}_amd64.deb"
    dest: "/var/tmp/qemu-upstream-aarch64_{{ qemu_version }}.deb"
    checksum: "sha256:{{ qemu_deb_sha256 }}"

- name: Install QEMU {{ qemu_version }}
  ansible.builtin.apt:
    deb: "/var/tmp/qemu-upstream-aarch64_{{ qemu_version }}.deb"
```

## Build locally

```bash
docker run --rm -v "$PWD:/w" -w /w ubuntu:24.04 bash build-deb.sh 11.1.2 out
```
