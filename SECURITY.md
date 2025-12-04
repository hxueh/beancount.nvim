# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < Latest | :x:               |

Only the latest release receives security updates. Users are encouraged to keep their installation up to date.

## Reporting a Vulnerability

If you discover a security vulnerability in beancount.nvim, please report it through [GitHub's private vulnerability reporting](https://github.com/hxueh/beancount.nvim/security/advisories/new).

**Do not** report security vulnerabilities through public GitHub issues.

### What to Include

- A clear description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Any suggested fixes (optional)

### Response Timeline

- **Acknowledgment**: Within 7 days of report submission
- **Initial assessment**: Within 21 days
- **Resolution timeline**: Communicated after assessment, depending on severity and complexity

## Scope

Security issues relevant to this project include:

- Command injection through Python subprocess execution
- Path traversal vulnerabilities in file handling
- Arbitrary code execution via malicious beancount files
- Unsafe deserialization of data from the Python integration

Issues **not** in scope:

- Vulnerabilities in Neovim itself
- Vulnerabilities in the upstream beancount Python library
- Denial of service through malformed input (unless it leads to code execution)

## Safe Harbor

We support responsible security research. If you act in good faith to identify and report vulnerabilities following this policy, we will:

- Not pursue legal action related to your research
- Work with you to understand and resolve the issue
- Credit you in the fix announcement (unless you prefer anonymity)
