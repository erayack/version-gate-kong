FROM kong:3.8.0

USER root

# Copy plugin source into the image and install via LuaRocks.
COPY . /tmp/version-gate
WORKDIR /tmp/version-gate
RUN luarocks make kong-plugin-version-gate-0.1.0-1.rockspec

USER kong
ENV KONG_PLUGINS=bundled,version-gate

