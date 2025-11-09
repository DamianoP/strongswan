FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y strongswan strongswan-pki iproute2 iptables ca-certificates 

RUN sed -i 's/^load =.*/load = random nonce aes sha1 sha2 kernel-netlink gmp pem pkcs1 x509 pubkey hmac stroke updown/' /etc/strongswan.d/charon.conf

RUN mkdir -p /etc/strongswan \
             /etc/ipsec.d/private \
             /etc/ipsec.d/certs \
             /etc/ipsec.d/cacerts && \
    apt install -y procps


COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 500/udp
EXPOSE 4500/udp

ENTRYPOINT ["/entrypoint.sh"]
