# AI Assistant Instructions for Public Images Repository

## Repository Purpose
This repo builds layered Docker images for data science environments:
- `datascience.docker` - Base Python/ML environment with security-hardened tooling
- `rust-datascience.docker` - Extends base with Rust ecosystem 
- `net-datascience.docker` - Extends base with .NET SDKs and interactive kernels

Built images are published as `mikaeluman/datascience:*` for reuse across projects.

## Architecture Principles

### Layered Image Strategy
- **Base image**: `datascience.docker` contains foundational tools (Python, AWS CLI, k8s tools)
- **Language extensions**: `rust-datascience.docker` and `net-datascience.docker` build FROM the base
- **Shared components**: Common tooling installed once in base layer for efficiency

### Security-First Binary Installation
All downloaded binaries use cryptographic verification:
- **AWS CLI**: GPG signature verification with pinned public key (`awscliv2-public-key.asc`)
- **Kubernetes tools**: SHA256 checksum verification from official sources
- **Pattern**: `ARG VERSION` → `curl binary + checksum` → `verify` → `install` → `cleanup`

## Critical Conventions

### User/Root Installation Pattern
```dockerfile
# System packages as root
RUN apt-get install system-packages
# Switch to user for dev tools  
USER $USER
# Language toolchains/packages as user
RUN uv add python-packages / cargo install tools
```

### Version Pinning Strategy
- All tools use `ARG VERSION=x.y.z` for easy updates
- Labels track installed versions: `org.opencontainers.image.tool.version=${VERSION}`
- PyTorch CPU-only via `pytorch.toml` configuration (toggleable with `USE_TORCH_GPU` build arg)

### Python Environment Management
- **uv** (not pip) for all Python package management
- Environment variables: `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, `UV_PYTHON_PREFERENCE=only-managed`
- Jupyter kernels installed both per-user and globally (`/usr/local/share/jupyter/kernels`)

### Rust Toolchain Integration
- Install via `rustup` as user, not system packages
- Cache mounts for `$USER/.cargo/registry` and `$USER/.cargo/git` 
- Components via `rustup component add`, tools via `cargo install`

### .NET Multi-SDK Setup
- Multiple SDK versions: `DOTNET_SDK_VERSIONS="8.0 9.0"`
- Global tool installation to `/usr/local/bin` for system-wide access
- Jupyter kernel registration for interactive notebooks

## Development Workflow

### Building Images
```bash
# Base image first
docker build -f datascience.docker -t mikaeluman/datascience:latest .

# Then language extensions
docker build -f rust-datascience.docker -t mikaeluman/datascience:rust .
docker build -f net-datascience.docker -t mikaeluman/datascience:net .
```

### Version Updates
1. Update `ARG VERSION=x.y.z` declarations
2. Test build locally  
3. Verify tool versions: `docker run --rm image:tag tool --version`
4. Update labels match ARG values

### Security Maintenance
- Check `awscliv2-public-key.asc` fingerprint against AWS docs when updating AWS CLI
- Verify SHA256 sources for k8s tools remain official
- Monitor base image CVEs: `ubuntu:24.04`

## Key Files to Understand
- `pytorch.toml` - uv configuration for CPU-only PyTorch (prevents GPU dependencies)
- `awscliv2-public-key.asc` - AWS CLI public key for signature verification
- `ARG USE_TORCH_GPU=false` - Build-time toggle for PyTorch variant selection