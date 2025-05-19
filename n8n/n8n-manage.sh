#!/bin/bash

# n8n Management Script - Simplified Version
# Usage: /opt/n8n-manage.sh [command]

N8N_DIR="/opt/n8n"
cd $N8N_DIR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

case "$1" in
    start)
        echo "Starting n8n..."
        docker-compose up -d
        sleep 5
        docker-compose ps
        ;;
    
    stop)
        echo "Stopping n8n..."
        docker-compose down
        ;;
    
    restart)
        echo "Restarting n8n..."
        docker-compose restart
        ;;
    
    status)
        echo "=== n8n Status ==="
        systemctl status n8n --no-pager -l
        echo ""
        echo "=== Containers ==="
        docker-compose ps
        ;;
    
    logs)
        service="${2:-n8n}"
        echo "Following logs for $service... (Press Ctrl+C to stop)"
        docker-compose logs -f "$service"
        ;;
    
    shell)
        container="${2:-n8n}"
        case "$container" in
            n8n)
                echo "Opening shell in n8n container..."
                docker-compose exec n8n /bin/sh
                ;;
            postgres)
                echo "Opening PostgreSQL shell..."
                docker-compose exec postgres psql -U n8n -d n8n
                ;;
            *)
                echo "Available containers: n8n, postgres"
                ;;
        esac
        ;;
    
    backup)
        BACKUP_DIR="/opt/n8n-backups"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mkdir -p $BACKUP_DIR
        
        echo "Creating backup..."
        # Database backup
        docker-compose exec -T postgres pg_dump -U n8n n8n | gzip > "$BACKUP_DIR/database_$TIMESTAMP.sql.gz"
        # Files backup
        tar czf "$BACKUP_DIR/files_$TIMESTAMP.tar.gz" -C data .
        # Config backup
        cp .env "$BACKUP_DIR/env_$TIMESTAMP"
        
        print_status "Backup created:"
        echo "  Database: $BACKUP_DIR/database_$TIMESTAMP.sql.gz"
        echo "  Files: $BACKUP_DIR/files_$TIMESTAMP.tar.gz"
        echo "  Config: $BACKUP_DIR/env_$TIMESTAMP"
        ;;
    
    restore)
        if [ -z "$2" ]; then
            echo "Usage: $0 restore <timestamp>"
            echo "Available backups:"
            ls -la /opt/n8n-backups/ | grep database_ | awk '{print $9}' | sed 's/database_//' | sed 's/\.sql\.gz//'
            exit 1
        fi
        
        BACKUP_DIR="/opt/n8n-backups"
        TIMESTAMP="$2"
        
        echo "Restoring from backup $TIMESTAMP..."
        read -p "This will overwrite current data. Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Restore cancelled"
            exit 0
        fi
        
        # Stop services
        docker-compose down
        
        # Restore database
        docker-compose up -d postgres
        sleep 10
        zcat "$BACKUP_DIR/database_$TIMESTAMP.sql.gz" | docker-compose exec -T postgres psql -U n8n -d n8n
        
        # Restore files
        rm -rf data/*
        tar xzf "$BACKUP_DIR/files_$TIMESTAMP.tar.gz" -C data/
        
        # Start all services
        docker-compose up -d
        print_status "Restore completed!"
        ;;
    
    update)
        echo "Updating n8n..."
        docker-compose pull
        docker-compose up -d
        print_status "Update completed!"
        ;;
    
    health)
        echo "=== Health Check ==="
        
        # Check containers
        if docker-compose ps | grep -q "Up"; then
            print_status "Containers are running"
        else
            print_error "Containers are not running"
        fi
        
        # Check n8n health
        if curl -s http://localhost:5678/healthz >/dev/null 2>&1; then
            print_status "n8n is responding"
        else
            print_error "n8n is not responding"
        fi
        
        # Check database
        if docker-compose exec -T postgres pg_isready -U n8n -d n8n >/dev/null 2>&1; then
            print_status "Database is ready"
        else
            print_error "Database connection failed"
        fi
        
        # Check disk space
        usage=$(df /opt/n8n | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ "$usage" -lt 80 ]; then
            print_status "Disk space OK ($usage% used)"
        else
            print_warning "Disk space low ($usage% used)"
        fi
        ;;
    
    env)
        case "$2" in
            edit)
                ${EDITOR:-nano} .env
                echo "Restart n8n to apply changes: $0 restart"
                ;;
            show)
                echo "=== Environment Configuration ==="
                grep -v -E '(PASSWORD|KEY|PASS|SECRET)' .env 2>/dev/null || echo "No .env file found"
                echo "(Sensitive values hidden)"
                ;;
            reload)
                echo "Reloading n8n with new environment..."
                docker-compose down
                docker-compose up -d
                ;;
            *)
                echo "Environment commands:"
                echo "  $0 env edit   - Edit .env file"
                echo "  $0 env show   - Show configuration"
                echo "  $0 env reload - Restart with new config"
                ;;
        esac
        ;;
    
    clean)
        echo "Cleaning up Docker resources..."
        docker-compose down
        docker system prune -f
        print_status "Cleanup completed"
        ;;
    
    reset)
        echo "WARNING: This will delete ALL n8n data!"
        read -p "Type 'DELETE' to confirm: " confirm
        if [ "$confirm" = "DELETE" ]; then
            docker-compose down -v
            rm -rf data/* postgres-data/*
            print_warning "n8n has been reset. Run '$0 start' to initialize."
        else
            echo "Reset cancelled"
        fi
        ;;
    
    *)
        echo "n8n Management Script"
        echo "Usage: $0 {command}"
        echo ""
        echo "Service Management:"
        echo "  start    - Start n8n"
        echo "  stop     - Stop n8n"  
        echo "  restart  - Restart n8n"
        echo "  status   - Show status"
        echo "  update   - Update to latest version"
        echo ""
        echo "Monitoring:"
        echo "  logs [service]  - Show logs (n8n|postgres)"
        echo "  shell [service] - Access container shell"
        echo "  health          - Check system health"
        echo ""
        echo "Data Management:"
        echo "  backup           - Create backup"
        echo "  restore <time>   - Restore from backup"
        echo "  clean            - Clean Docker resources"
        echo "  reset            - Delete all data"
        echo ""
        echo "Configuration:"
        echo "  env edit   - Edit environment file"
        echo "  env show   - Show configuration"
        echo "  env reload - Apply new configuration"
        echo ""
        echo "Examples:"
        echo "  $0 logs           - Follow n8n logs"
        echo "  $0 backup         - Create backup"
        echo "  $0 restore 20241201_120000 - Restore backup"
        ;;
esac
