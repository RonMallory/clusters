# Personal Development Overlay: ron-mallory

This overlay extends the base `clusters/local/` configuration with personal customizations.

## Details
- **Developer**: ron.mallory@umbrage.com
- **Cluster**: local-ron-mallory
- **Branch**: init/dev-xp
- **Created**: Tue Sep 16 16:06:45 MST 2025

## Structure
- `infrastructure/` - Infrastructure overlay (cert-manager, CNPG, etc.)
- `apps/` - Applications overlay
- Both inherit from `../../` (base local cluster)

## Usage
```bash
# Apply this overlay
kustomize build . | kubectl apply -f -

# Check what would be applied
kustomize build .
```

## Customization
Add your personal resources, patches, or configuration changes to the respective kustomization.yaml files.
