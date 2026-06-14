FROM perl:5.38-slim-bookworm
RUN cpanm -n JSON
WORKDIR /app
COPY server.pl .
RUN chmod +x server.pl
EXPOSE 8088
CMD ["./server.pl"]
