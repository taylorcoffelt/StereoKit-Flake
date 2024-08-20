{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils}:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = {
          default = let
            # StereoKit
            StereoKitSource = pkgs.fetchFromGitHub {
              owner = "StereoKit";
              repo = "StereoKit";
              rev = "d13782c6c96771d0498361917a8e2621fa7d9a59";
              sha256 = "sha256-t7m8QL8+5Iyt9BNfBxtIWEnD1zn0pb4zmzNiBV1KJvc=";
            };

            # General Dependancies
            openxr_loader = pkgs.fetchFromGitHub {
              owner = "KhronosGroup";
              repo = "OpenXR-SDK";
              rev = "288d3a7ebc1ad959f62d51da75baa3d27438c499";
              sha256 = "sha256-RdmnBe26hqPmqwCHIJolF6bSmZRmIKVlGF+TXAY35ig=";
            };
            meshoptimizer = pkgs.fetchFromGitHub {
              owner = "zeux";
              repo = "meshoptimizer";
              rev = "c21d3be6ddf627f8ca852ba4b6db9903b0557858";
              sha256 = "sha256-QCxpM2g8WtYSZHkBzLTJNQ/oHb5j/n9rjaVmZJcCZIA=";
            };
            basis_universal = pkgs.fetchFromGitHub {
              owner = "BinomialLLC";
              repo = "basis_universal";
              rev = "900e40fb5d2502927360fe2f31762bdbb624455f";
              sha256 = "sha256-zBRAXgG5Fi6+5uPQCI/RCGatY6O4ELuYBoKrPNn4K+8=";
            };

            sk_gpu = let
              zip = builtins.fetchurl {
                url =
                  "https://github.com/StereoKit/sk_gpu/releases/download/v2024.8.16/sk_gpu.v2024.8.16.zip";
                sha256 = "sha256:0rdll3q9gvr36b9kxn30qxm54v2p3b2d4inc8gn1majnb5jcykas";
              };
            in pkgs.stdenv.mkDerivation {
              name = "sk_gpu";
              src = zip;
              unpackPhase = ''
                unzip -d $out ${zip}
              '';
              nativeBuildInputs = [ pkgs.unzip ];
            };

            #CPM
            CPM_CONFIG_FILE = builtins.head (builtins.split "\n"
              (builtins.readFile "${StereoKitSource}/cmake/CPM.cmake"));
            CPM_VERSION_REGEX = "set\\(CPM_DOWNLOAD_VERSION ([0-9\\.]+)\\)";
            CPM_DOWNLOAD_VERSION =
              builtins.head (builtins.match CPM_VERSION_REGEX CPM_CONFIG_FILE);
            CPM_FILE = pkgs.fetchurl {
              url =
                "https://github.com/cpm-cmake/CPM.cmake/releases/download/v${CPM_DOWNLOAD_VERSION}/CPM.cmake";
              sha256 = "sha256-g+XrcbK7uLHyrTjxlQKHoFdiTjhcI49gh/lM38RK+cU=";
            };

            buildFlags = {
              SK_BUILD_SHARED_LIBS = "OFF";
              SK_BUILD_TESTS = "OFF";
              SK_PHYSICS = "OFF";

              CPM_USE_LOCAL_PACKAGES = "ON";
              CPM_LOCAL_PACKAGES_ONLY = "ON";
              CPM_DOWNLOAD_ALL = "OFF";

              CPM_openxr_loader_SOURCE = openxr_loader;
              CPM_meshoptimizer_SOURCE = meshoptimizer;
              CPM_basis_universal_SOURCE = basis_universal;
              CPM_sk_gpu_SOURCE = "./sk_gpu";
            };
            formattedFlags = map (k:
              let key = "-D" + k;
              in "${key}=${builtins.getAttr k buildFlags}")
              (builtins.attrNames buildFlags);
          in pkgs.stdenv.mkDerivation {
            name = "StereoKit";
            src = StereoKitSource;

            LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib";

            nativeBuildInputs = [
              pkgs.cmake
              pkgs.pkg-config
              pkgs.llvmPackages.libcxxClang
              pkgs.patchelf
            ];
            buildInputs = [
              pkgs.libGL
              pkgs.mesa
              pkgs.xorg.libX11.dev
              pkgs.xorg.libXfixes
              pkgs.fontconfig
              pkgs.libxkbcommon
            ];

            postPatch =
              let libPath = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
              in ''
                mkdir -p build/cmake
                echo "Setting up CPM V${CPM_DOWNLOAD_VERSION};"
                cp ${CPM_FILE} build/cmake/CPM_${CPM_DOWNLOAD_VERSION}.cmake;
                mkdir -p build/sk_gpu;
                cp -R ${sk_gpu}/* build/sk_gpu/;
                chmod -R 777 build/sk_gpu;
                ldd build/sk_gpu/tools/linux_x64/skshaderc
                export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib";
                patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                  --set-rpath "${libPath}" \
                build/sk_gpu/tools/linux_x64/skshaderc
              '';

            cmakeFlags = formattedFlags;



            # Correct issues with paths in .pc files
            installPhase =  ''
                ${pkgs.sd}/bin/sd --string-mode '$${"{prefix}//nix/store"}' '/nix/store' **/*.pc
                ls -lah ..
                mkdir -p $out/bin
                cp -r ./../bin $out
            '';
          };
        };
      });
}
