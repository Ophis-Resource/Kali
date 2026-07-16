`Hello`
`Hi`
`Bye Bye`

use `sudo docker rm -f $(sudo docker ps -aq) 2>/dev/null || true && sudo docker system prune -af --volumes`

windows `docker rm -f (docker ps -aq) 2>$null; docker system prune -af --volumes; docker volume rm (docker volume ls -q) 2>$null; docker network rm (docker network ls -q | Select-Object -Skip 3) 2>$null`
