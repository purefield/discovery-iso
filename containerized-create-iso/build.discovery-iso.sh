./build.gather_facts.sh
podman build -t create-discovery-iso -f Containerfile.discovery-iso
podman tag localhost/create-discovery-iso:latest quay.io/dds/discovery-iso:latest
podman push quay.io/dds/discovery-iso:latest

