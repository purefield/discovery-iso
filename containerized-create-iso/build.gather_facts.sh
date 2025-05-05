podman build -t coreos-diagnostic -f Containerfile
podman save --format oci-archive -o coreos-diagnostic.oci coreos-diagnostic
