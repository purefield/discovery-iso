mkdir -p build
podman run --rm --interactive \
  --security-opt label=disable \
  --volume "$PWD/build":/work/build \
  --workdir /work \
  -e HOME="/work" \
  create-discovery-iso -c './create-iso.sh'
