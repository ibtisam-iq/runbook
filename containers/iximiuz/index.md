# iximiuz Labs

I first came across iximiuz Labs while preparing for my CKA and CKAD exams. It appeared alongside Killercoda and KodeKloud in the Kubernetes official docs as a recommended playground. I tried it, it was noticeably amazing, and after passing these exams I purchased its Lifetime Premium.

iximiuz Labs is a browser-based microVM lab platform. What sets it apart: it supports **custom OCI images mounted as a block device rootfs** — meaning we can build a fully configured image, push it to GHCR, and the platform boots it as a live VM with systemd as PID 1.

I build custom rootfs images to take advantage of exactly that. Starting from an Ubuntu 24.04 base, I layered five images — each published to GHCR via GitHub Actions — and use them to spin up purpose-built playgrounds on demand. This is an ongoing learning; more images and playgrounds will be added.

---

## rootfs Images

| Image | Runbook | GHCR |
|---|---|---|
| `ubuntu-24-04-rootfs` | [Setup Guide](./rootfs/setup-ubuntu-24-04-rootfs-base-image.md) | [ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs](https://github.com/ibtisam-iq/silver-stack/pkgs/container/ubuntu-24-04-rootfs) |
| `dev-machine-rootfs` | [Setup Guide](./rootfs/setup-dev-machine-rootfs-image.md) | [ghcr.io/ibtisam-iq/dev-machine-rootfs](https://github.com/ibtisam-iq/silver-stack/pkgs/container/dev-machine-rootfs) |
| `jenkins-rootfs` | [Setup Guide](./rootfs/setup-jenkins-rootfs-image.md) | [ghcr.io/ibtisam-iq/jenkins-rootfs](https://github.com/ibtisam-iq/silver-stack/pkgs/container/jenkins-rootfs) |
| `sonarqube-rootfs` | [Setup Guide](./rootfs/setup-sonarqube-rootfs-image.md) | [ghcr.io/ibtisam-iq/sonarqube-rootfs](https://github.com/ibtisam-iq/silver-stack/pkgs/container/sonarqube-rootfs) |
| `nexus-rootfs` | [Setup Guide](./rootfs/setup-nexus-rootfs-image.md) | [ghcr.io/ibtisam-iq/nexus-rootfs](https://github.com/ibtisam-iq/silver-stack/pkgs/container/nexus-rootfs) |

---

## Playgrounds

Each rootfs powers a dedicated playground. The CI/CD Stack playground combines Jenkins, SonarQube, and Nexus alongside a Dev Machine node into a single four-node Flexbox environment.

| Playground | URL |
|---|---|
| Dev Machine | [Open](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) |
| Jenkins | [Open](https://labs.iximiuz.com/playgrounds/SilverStack-jenkins-server-63fe430c) |
| SonarQube | [Open](https://labs.iximiuz.com/playgrounds/SilverStack-sonarqube-server-7761f36f) |
| Nexus | [Open](https://labs.iximiuz.com/playgrounds/SilverStack-nexus-server-9a3f87e9) |
| CI/CD Stack | [Open](https://labs.iximiuz.com/playgrounds/SilverStack-CICD-Stack-1766a8a1) |
