mkdir -p build
podman run --rm --interactive \
  --security-opt label=disable \
  --volume "$PWD":/work/host \
  --workdir /work \
  -e HOME="/work" \
  create-discovery-iso -c './create-iso.sh'
