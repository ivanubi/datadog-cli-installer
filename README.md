# PM2 Docker Application

This project demonstrates a Node.js application managed by PM2 running in a Docker container based on Ubuntu 22.04.

## Features

- **Base Image**: Ubuntu 22.04 LTS
- **Runtime**: Node.js 18.x
- **Process Manager**: PM2 with cluster mode
- **Application**: Express.js REST API
- **Security**: Non-root user execution
- **Health Checks**: Built-in health endpoints

## Project Structure

```
├── Dockerfile              # Docker image configuration
├── app.js                 # Main Express application
├── package.json           # Node.js dependencies
├── ecosystem.config.js    # PM2 configuration
├── .dockerignore         # Docker ignore file
└── README.md             # This file
```

## API Endpoints

- `GET /` - Welcome message with app info
- `GET /health` - Health check endpoint
- `GET /info` - Detailed application information

## Building the Docker Image

```bash
# Build the image
docker build -t pm2-docker-app .

# Build with a specific tag
docker build -t pm2-docker-app:1.0.0 .
```

## Running the Container

### Basic Run
```bash
# Run the container
docker run -d -p 3000:3000 --name pm2-app pm2-docker-app

# Run with custom port mapping
docker run -d -p 8080:3000 --name pm2-app pm2-docker-app
```

### Run with Environment Variables
```bash
docker run -d \
  -p 3000:3000 \
  -e NODE_ENV=production \
  -e PORT=3000 \
  --name pm2-app \
  pm2-docker-app
```

### Run with Volume for Logs
```bash
docker run -d \
  -p 3000:3000 \
  -v $(pwd)/logs:/app/logs \
  --name pm2-app \
  pm2-docker-app
```

## Managing the Container

```bash
# Check container status
docker ps

# View logs
docker logs pm2-app

# Follow logs in real-time
docker logs -f pm2-app

# Execute commands inside the container
docker exec -it pm2-app bash

# Check PM2 status inside the container
docker exec pm2-app pm2 status

# Stop the container
docker stop pm2-app

# Remove the container
docker rm pm2-app
```

## Testing the Application

Once the container is running, you can test the endpoints:

```bash
# Test the main endpoint
curl http://localhost:3000

# Test health check
curl http://localhost:3000/health

# Test info endpoint
curl http://localhost:3000/info
```

## PM2 Features in this Setup

- **Cluster Mode**: Utilizes all available CPU cores
- **Auto Restart**: Automatically restarts on crashes
- **Memory Management**: Restarts if memory usage exceeds 500MB
- **Health Monitoring**: Built-in health checks
- **Graceful Shutdown**: Proper cleanup on container stop
- **Log Management**: Centralized logging configuration

## Development

For local development without Docker:

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Start with PM2 locally
npm run pm2
```

## Environment Variables

- `NODE_ENV`: Application environment (default: production)
- `PORT`: Server port (default: 3000)

## Docker Image Details

- **Base**: Ubuntu 22.04
- **Node.js**: 18.x LTS
- **PM2**: Latest version
- **User**: Non-root user (appuser)
- **Working Directory**: /app
- **Exposed Port**: 3000 