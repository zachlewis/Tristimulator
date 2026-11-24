name = "tristimulator"
version = "1.0.0"
uuid = "05c1c0d1c3784ad8864acc9588204920"

description = (
    "Native Mac viewer for OpenEXR and other formats, with OpenColorIO "
    "colour management, dynamic ACES 2 rendering and EDR integration."
)
authors = ["Alexander Fry"]
help = "https://github.com/alexfry/Tristimulator"

tags = ["viewer", "exr", "ocio", "aces", "colour", "macos"]

requires = [
    "platform-osx",
    "arch-arm64",
]

private_build_requires = [
    "cmake-3",
]

build_command = "bash {root}/rez/build.sh {install}"

tools = ["tristimulator"]

def commands():
    env.PATH.prepend("{root}/bin")

    # If the resolved env has no $OCIO, point at the bundled ACES v2 config.
    import os
    if not os.environ.get("OCIO"):
        env.OCIO = "{root}/ocio/studio-config-v4.0.0_aces-v2.0_ocio-v2.5.ocio"
