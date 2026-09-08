#!/bin/bash

# Ensure shared network exists
if ! docker network inspect shared >/dev/null 2>&1; then
    docker network create --subnet=172.20.0.0/24 shared
fi

COMPOSE_FILES="-f docker-compose.db.yml -f docker-compose.app.yml -f docker-compose.mon.yml"

echo "Select an action for AnnoGrid:"
echo "1) Start/Update All (Recommended)"
echo "2) Stop All Stacks"
echo "3) Restart Databases Only"
echo "4) View Logs (Follow)"
echo "q) Quit"

read -p "Option: " choice

case $choice in
    1)
        docker compose $COMPOSE_FILES up -d --remove-orphans
        ;;
    2)
        docker compose $COMPOSE_FILES down
        ;;
    3)
        docker compose -f docker-compose.db.yml restart
        ;;
    4)
        docker compose $COMPOSE_FILES logs -f --tail=100
        ;;
    *)
        exit 0
        ;;
esac
