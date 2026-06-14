FROM php:8.3-cli-bookworm
WORKDIR /app
COPY server.php .
RUN chmod +x server.php
EXPOSE 8087
CMD ["./server.php"]
