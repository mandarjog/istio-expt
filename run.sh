#!/bin/bash


export QPS="3000"
export CONNECTIONS="8"
export PROXY_IMG=istio/proxyv2:1.6.4
export WORKERS="2"
export CPUS=1.0
export MASK_BASE=2 # 7 == 111b denotes 3 cpus 
export CFGDIR=/config
export WDIR=$(dirname $0)
export WDIR=$(cd ${WDIR};pwd)
export FORTIO=${FORTIO:-fortio}
export PROXY_ADDR=10.128.0.49

set -ex

function runProxy() {
	local base_id=2
	local cpu_mask="0x${MASK_BASE}" # assigning 4 cpus
	local proxy=$1  # proxy or server
	local istio=$2  # base or istio

	if [[ "${proxy}" == "proxy" ]];then
		base_id=4
		cpu_mask="0x${MASK_BASE}0"
	fi
	local service_node="${proxy}-${istio}"

	docker run --rm --cpus="${CPUS}" --network host --name "perf-${proxy}" -d -v "${WDIR}:${CFGDIR}" --entrypoint=/usr/local/bin/envoy "${PROXY_IMG}" --concurrency "${WORKERS}" -c "${CFGDIR}/${proxy}_${istio}.yaml" --base-id "${base_id}" --service-node "${service_node}"

	sleep 2
	local envoy_pid=$(ps aux | grep ${service_node} |grep envoy | awk '{print $2}')

	sudo taskset -p "${cpu_mask}" "${envoy_pid}"
}

function runProxies() {
	local istio=$1  # base or istio
	runProxy proxy "${istio}"
	runProxy server "${istio}"
}

function stopProxies() {
	docker stop perf-proxy
	docker stop perf-server
}

function runTest() {
	local labels="$1_w${WORKERS}_cpu${CPUS}"
	taskset 0x7 "${FORTIO}" load -qps "${QPS}" -t 120s -a -r 0.00005 -labels "${labels}" -c "${CONNECTIONS}" http://${PROXY_ADDR}:9999
}

testmode=$1

case "${testmode}" in
	base)
	;;
	istio)
	;;
	*)
	echo "Only istio|base are valid modes"
	exit -1
esac

fn=$2
case "${fn}" in
	setup)
		runProxies "${testmode}"
		;;
	test)
		runTest "${testmode}"
		;;
	shutdown)
		stopProxies "${testmode}"
		;;
	*)
	echo "setup|test|shutdown"
	exit -1
esac

