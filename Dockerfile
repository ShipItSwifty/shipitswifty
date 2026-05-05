# ShipItSwifty — Linux development / test image
#
# Supported targets on Linux:
#   GradleKit, ShipItKit (core), CLI, ShipItKitTests, GradleKitTests, CLITests
#
# macOS-only targets (skipped on Linux):
#   XcodeBuildKit, XcodeGenKit, XcodeBuildKitTests, XcodeGenKitTests, IntegrationTests

FROM swift:6.3.1-noble

WORKDIR /workspace

# Resolve dependencies as a separate cached layer.
# This layer is only invalidated when Package.swift or Package.resolved changes,
# keeping iterative source-only rebuilds fast.
COPY Package.swift Package.resolved ./
RUN swift package resolve

# Copy the rest of the source tree.
COPY . .

# Default: interactive shell so developers can run arbitrary commands.
# To run tests directly:  docker run --rm <image> swift test --skip IntegrationTests --skip XcodeBuildKitTests --skip XcodeGenKitTests
CMD ["/bin/bash"]
