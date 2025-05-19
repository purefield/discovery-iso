export BASE64STRING=$(cat format.sh setup-network.sh | base64 -w0 )
envsubst < diagnostic.bu.tpl > diagnostic.bu
