FROM fluent/fluent-bit:latest

COPY fluent-bit.conf /fluent-bit/etc/fluent-bit.conf
COPY parsers.conf /fluent-bit/parsers.conf
COPY plugins.conf /fluent-bit/plugins.conf

CMD ["/fluent-bit/bin/fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.conf"]
