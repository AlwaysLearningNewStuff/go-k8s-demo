#!/bin/bash

echo "🧹 Cleaning up Go K8s Demo..."
echo ""

# Check if cluster exists
if ! kind get clusters 2>/dev/null | grep -q "demo"; then
    echo "ℹ️  Kind cluster 'demo' does not exist. Nothing to clean up."
    exit 0
fi

echo "📋 Current cluster status:"
kubectl get all -n go-k8s-demo 2>/dev/null || echo "Namespace 'go-k8s-demo' not found"
echo ""

read -p "❓ Are you sure you want to delete the Kind cluster 'demo'? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

echo ""
echo "🗑️  Deleting Kind cluster 'demo'..."
kind delete cluster --name demo

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "To redeploy, run:"
echo "   ./deploy.sh"
