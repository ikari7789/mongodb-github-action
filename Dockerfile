FROM docker:stable

COPY start-mongodb.sh /start-mongodb.sh
RUN chmod +x /start-mongodb.sh

COPY cleanup.sh /cleanup.sh
RUN chmod +x /cleanup.sh

VOLUME /tmp

ENTRYPOINT ["/start-mongodb.sh"]
