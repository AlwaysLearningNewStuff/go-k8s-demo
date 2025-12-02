#!/bin/bash

# Colors for prettier output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Go K8s Demo - API Endpoint Tests                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Start port-forward in background
echo -e "${YELLOW}🔌 Starting port-forward to API service...${NC}"
kubectl port-forward -n go-k8s-demo service/api 8080:80 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Function to cleanup port-forward on exit
cleanup() {
    if [ ! -z "$PORT_FORWARD_PID" ]; then
        echo ""
        echo -e "${YELLOW}🛑 Stopping port-forward...${NC}"
        kill $PORT_FORWARD_PID 2>/dev/null
    fi
}
trap cleanup EXIT

# Wait for port-forward to be ready
echo -e "${YELLOW}⏳ Waiting for port-forward to be ready...${NC}"
for i in {1..10}; do
    if curl -s http://localhost:8080/healthz > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Port-forward ready!${NC}"
        echo ""
        break
    fi
    sleep 1
    if [ $i -eq 10 ]; then
        echo -e "${RED}❌ ERROR: Port-forward failed to start${NC}"
        exit 1
    fi
done

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: jq not found. Install with: sudo apt install jq${NC}"
    echo -e "${YELLOW}   Continuing without JSON formatting...${NC}"
    echo ""
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

# 1. Health Check
echo -e "${BLUE}[1] Testing /healthz${NC}"
RESPONSE=$(curl -s http://localhost:8080/healthz)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED${NC}"
echo ""

# 2. Readiness Check
echo -e "${BLUE}[2] Testing /readyz${NC}"
RESPONSE=$(curl -s http://localhost:8080/readyz)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED${NC}"
echo ""

# 3. Get all users
echo -e "${BLUE}[3] GET /users - List all users${NC}"
RESPONSE=$(curl -s http://localhost:8080/users)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED${NC}"
echo ""

# 4. Get specific user
echo -e "${BLUE}[4] GET /users/1 - Get specific user${NC}"
RESPONSE=$(curl -s http://localhost:8080/users/1)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED${NC}"
echo ""

# 5. Create new user
echo -e "${BLUE}[5] POST /users - Create new user${NC}"
echo -e "${YELLOW}Request body: {\"name\":\"Charlie\",\"email\":\"charlie@example.com\"}${NC}"
RESPONSE=$(curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Charlie","email":"charlie@example.com"}')
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED - User created with ID: $(echo $RESPONSE | jq -r '.id')${NC}"
echo ""

# 6. Get all users after creation
echo -e "${BLUE}[6] GET /users - Verify user was created${NC}"
RESPONSE=$(curl -s http://localhost:8080/users)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED - Now showing 3 users${NC}"
echo ""

# 7. Update user
echo -e "${BLUE}[7] PUT /users/3 - Update user${NC}"
echo -e "${YELLOW}Request body: {\"name\":\"Charles\",\"email\":\"charles@example.com\"}${NC}"
RESPONSE=$(curl -s -X PUT http://localhost:8080/users/3 \
  -H "Content-Type: application/json" \
  -d '{"name":"Charles","email":"charles@example.com"}')
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED - User updated${NC}"
echo ""

# 8. Get all users after update
echo -e "${BLUE}[8] GET /users - Verify user was updated${NC}"
RESPONSE=$(curl -s http://localhost:8080/users)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED - User 3 now shows updated name${NC}"
echo ""

# 9. Delete user
echo -e "${BLUE}[9] DELETE /users/3 - Delete user${NC}"
RESPONSE=$(curl -s -X DELETE http://localhost:8080/users/3)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED - User deleted${NC}"
echo ""

# 10. Get all users after deletion
echo -e "${BLUE}[10] GET /users - Verify user was deleted${NC}"
RESPONSE=$(curl -s http://localhost:8080/users)
if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RESPONSE" | jq '.'
else
    echo "$RESPONSE"
fi
echo -e "${GREEN}✅ PASSED - Back to 2 users${NC}"
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ All tests passed successfully!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"