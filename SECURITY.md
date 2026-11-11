# Security policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release | yes |
| `main` | yes |
| Older releases | no |

## Reporting a vulnerability

Report privately through GitHub: **Security → Report a vulnerability** on this repository. Email to v@valdemar.ai also works. The process is described at [heyvaldemar.com/security](https://heyvaldemar.com/security/).

You can expect an acknowledgment within 7 days. There is no bounty program; valid, responsibly disclosed reports are credited in the changelog. Please do not open public issues for security reports.

## What this repository is

A benchmark, not a hosted service. It reads other repositories' releases and runs them on kind. A report here is most likely one of three things: a way to make a run publish a result its logs do not carry, a way to make `scripts/sources.sh` accept a release it should refuse, or a way for what this repository adds beside a boundary to open more than the model's one port. A weakness in a boundary itself belongs to the repository that releases it.

## Supply chain

- Each boundary is a release pinned in `sources.lock` by tag and sha256, and is read only after its cosign signature and its SLSA provenance verify.
- Container images are pinned by digest, and CI fails on one that is not.
- GitHub Actions are pinned by commit SHA; CLI tools by version and sha256 (`tools.lock`); CI images by digest (`ci-images.pins`).

## Credentials

None. The models are open weights on CPU or stand-ins without weights, and nothing in this repository or its CI stores a credential.
