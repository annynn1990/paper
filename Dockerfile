FROM mariadb:11.4

RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

COPY db-health.py /usr/local/bin/db-health.py
ENV PORT=10000
EXPOSE 10000

# Render web services need an HTTP listener. MariaDB remains private on TCP 3306;
# this tiny HTTP endpoint exposes only health status, never database contents.
ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["docker-entrypoint.sh mariadbd & exec python3 /usr/local/bin/db-health.py"]
