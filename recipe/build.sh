#!/usr/bin/env bash

set -o xtrace -o nounset -o pipefail -o errexit

# Build each tool with dotnet publish
build() {
    bin_name=$1
    dotnet publish --no-self-contained src/Tools/${bin_name}/${bin_name}.csproj --output ${PREFIX}/libexec/${PKG_NAME}
    rm ${PREFIX}/libexec/${PKG_NAME}/${bin_name}
}

export -f build

# Crate bash and batch wrapper for each tool
env_script() {
bin_name=$1
tee ${PREFIX}/bin/${bin_name} << EOF
#!/bin/sh
exec \${DOTNET_ROOT}/dotnet exec \${CONDA_PREFIX}/libexec/dotnet-diagnostics/${bin_name}.dll "\$@"
EOF
chmod +x ${PREFIX}/bin/${bin_name}

tee ${PREFIX}/bin/${bin_name}.cmd << EOF
call %DOTNET_ROOT%\dotnet exec %CONDA_PREFIX%\libexec\dotnet-diagnostics\\${bin_name}.dll %*
EOF
}

export -f env_script

mkdir -p ${PREFIX}/bin
mkdir -p ${PREFIX}/libexec/${PKG_NAME}
ln -sf ${DOTNET_ROOT}/dotnet ${PREFIX}/bin

# This file contains methods that are polyfilled for .NET <8.0, but the check is hard-coded to .NET 8.0
sed -i 's/NET8_0/NET9_0/g' src/Microsoft.Diagnostics.NETCore.Client/DiagnosticsIpc/IpcSocket.cs

# Set .NET version to 9.0
framework_version="$(dotnet --version | sed -e 's/\..*//g').0"
sed -i "s?<NetCoreAppMinVersion>.*</NetCoreAppMinVersion>?<NetCoreAppMinVersion>${framework_version}</NetCoreAppMinVersion>?" Directory.Build.props

# Temporarily pin Arcade.Sdk to latest version that support .NET 9.0 - newer versions needs .NET 10.0 beta
jq 'del(.tool)' | jq '."msbuild-sdks"."Microsoft.DotNet.Arcade.Sdk" = "10.0.0-beta.24564.1"' < global.json > global.json.new
rm -rf global.json
mv global.json.new global.json

tools=(dotnet-counters dotnet-dsrouter dotnet-dump dotnet-gcdump dotnet-sos dotnet-stack dotnet-trace)

# Call functions to build each tool,create wrappers
printf "%s\n" "${tools[@]}" | xargs -I % bash -c "build %"
printf "%s\n" "${tools[@]}" | xargs -I % bash -c "env_script %"
printf "%s\n" "${tools[@]}" | xargs -I % bash -c "dotnet-project-licenses --input src/Tools/%/%.csproj -t -d license-files"

rm -rf ${PREFIX}/libexec/${PKG_NAME}/shims
rm ${PREFIX}/bin/dotnet
