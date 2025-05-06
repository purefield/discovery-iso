podman build -t coreos-diagnostic -f Containerfile.diagnostic
podman save --format oci-archive -o coreos-diagnostic.oci coreos-diagnostic
