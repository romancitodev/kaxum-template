FROM node:22-slim
RUN npm install -g @liam-hq/cli serve
WORKDIR /erd
# Junta las migraciones (en orden por nombre) y regenera el diagrama cada vez que arranca el contenedor.
CMD ["sh", "-c", "cat /migrations/*.sql > /tmp/schema.sql && liam erd build --format postgres --input /tmp/schema.sql --output-dir /erd/dist && serve /erd/dist -l 3000"]
