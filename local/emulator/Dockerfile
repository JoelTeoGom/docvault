FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal

ARG TARGETARCH

RUN case "$TARGETARCH" in arm64) rpmArch=aarch64 ;; *) rpmArch=x86_64 ;; esac \
    && curl -fsSL -o /tmp/aws-emulator.rpm "https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/latest/aws-emulator-$rpmArch.rpm" \
    && rpm -ivh /tmp/aws-emulator.rpm \
    && rm /tmp/aws-emulator.rpm

EXPOSE 9297

ENTRYPOINT ["aws-emulator", "-b", "0.0.0.0"]
