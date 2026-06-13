CLUSTER_NAME ?= ebpflogs
AWS_REGION ?= us-west-2
CORALOGIX_PRIVATE_KEY ?=

.PHONY: eks-recreate eks-up deploy-eks test clean-eks

eks-recreate:
	RECREATE=true CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) ./scripts/setup-eks.sh

eks-up:
	@CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) ./scripts/setup-eks.sh

deploy-eks:
	@CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) CORALOGIX_PRIVATE_KEY=$(CORALOGIX_PRIVATE_KEY) ./scripts/deploy-eks.sh

test:
	@./scripts/test-traces.sh

test-go:
	@APP=logdemo-go ./scripts/test-traces.sh

test-java:
	@APP=logdemo-java ./scripts/test-traces.sh

traffic:
	@kubectl -n ebpflogs logs -l app=logdemo-go -c traffic -f

traffic-cronjob:
	@kubectl -n ebpflogs apply -f k8s/traffic-cronjob.yaml

clean-eks:
	eksctl delete cluster --name $(CLUSTER_NAME) --region $(AWS_REGION) --wait

all: eks-recreate deploy-eks test
