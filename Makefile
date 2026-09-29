# Entry points. Logic lives in scripts/ so it runs the same on GNU make 3.81
# (macOS default) and newer versions on Linux.
.PHONY: up down test status

up:     ## Create the cluster and deploy everything, then run the smoke test
	@./scripts/up.sh

down:   ## Delete the cluster and all local state
	@./scripts/down.sh

test:   ## GET /ping through the gateway must return "pong"
	@./scripts/test.sh

status: ## Show what is running
	@for ns in gko-system gravitee pong; do \
		echo "--- $$ns"; KUBECONFIG=.kube/config kubectl -n $$ns get pods,svc; \
	done
	@echo "--- APIs"; KUBECONFIG=.kube/config kubectl -n gravitee get apiv4definitions
