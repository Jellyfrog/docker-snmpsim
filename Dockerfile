# syntax=docker/dockerfile:1

# ---- Build stage: install Python deps into an isolated virtualenv ----
# Debian's own python3 is the same interpreter, at the same path
# (/usr/bin/python3), as in the distroless runtime, so the venv works there.
FROM debian:trixie-slim AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && apt-get install -y --no-install-recommends python3-venv \
 && python3 -m venv /opt/venv

# Pin snmpsim so the image always picks up the expected release. pip is only
# needed here, so remove it from the venv afterwards.
RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/venv/bin/pip install --disable-pip-version-check \
        cryptography pysnmp pysmi snmpsim==1.2.1 \
 && /opt/venv/bin/pip uninstall -y pip

# snmpsim searches <sys.prefix>/snmpsim/{data,variation} (snmpsim/confdir.py).
# sys.prefix is now the venv, so link it to /usr/local/snmpsim, the documented
# mount path.
RUN ln -s /usr/local/snmpsim /opt/venv/snmpsim

# ---- base: shared runtime (distroless, no shell, runs as uid 65532) ----
FROM gcr.io/distroless/python3-debian13:nonroot AS base

# Metadata
LABEL maintainer="support@lextudio.com"
LABEL version="1.1"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY --from=builder /opt/venv /opt/venv

# ---- snmptrapd: trap/inform receiver ----
FROM base AS snmptrapd

LABEL description="PySNMP trap/inform receiver from docker-snmpsim"

COPY snmptrapd.py /opt/snmptrapd.py

EXPOSE 1162/udp

ENTRYPOINT ["/opt/venv/bin/python", "/opt/snmptrapd.py"]

# ---- snmpsim: the simulator (last, so it is the default build target) ----
FROM base AS snmpsim

LABEL description="Docker image for running snmpsim (PySNMP Simulator)"

COPY data /usr/local/snmpsim/data

EXPOSE 1161/udp

# snmpsim only handles SIGTERM when daemonized, and as PID 1 an unhandled
# SIGTERM is ignored. Python turns SIGINT into KeyboardInterrupt, which
# snmpsim handles.
STOPSIGNAL SIGINT

# Extra snmpsim flags can be given as container arguments.
ENTRYPOINT ["/opt/venv/bin/snmpsim-command-responder", "--agent-udpv4-endpoint=0.0.0.0:1161"]
