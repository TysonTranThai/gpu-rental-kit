# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| Latest release (`main`) | ✅ |

Patch releases are made for security issues in the latest release. Older
releases are not supported — upgrade to the latest release.

## Reporting a vulnerability

Please **do not open a public issue** for security vulnerabilities. Instead,
report privately via **GitHub's private vulnerability reporting**:

1. Go to https://github.com/TysonTranThai/gpu-rental-kit/security/advisories
2. Click **New draft security advisory**
3. Describe the vulnerability, its impact, and steps to reproduce

You can also email the maintainers at the address shown on the repository
profile page.

### What to include

- The affected file(s) and version(s)
- A minimal reproduction
- The impact if exploited
- (Optional) a suggested fix

We aim to acknowledge reports within **5 business days** and will keep you
updated as we triage. If the issue is confirmed, we'll fix it, release a
patch, and credit the reporter (if they wish).

## Security posture of this project

By design, GPU Rental Kit:

- **Binds inference servers to `127.0.0.1` by default** (`EXPOSE_PUBLICLY=false`)
- **Never installs NVIDIA drivers** (avoids breaking provider images)
- **Never stores credentials** — secrets come from the environment
  (`HF_TOKEN`, `VLLM_API_KEY`, …) and are git-ignored
- **Never exposes the API publicly** without an explicit, deliberate flag

If you find a way around any of these guarantees, that's exactly the kind of
report we want.
