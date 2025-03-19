SPIKEINTERFACE_VERSION=$(grep '^spikeinterface==' requirements.txt | cut -d'=' -f3)

docker tag ghcr.io/allenneuraldynamics/aind-ephys-hybrid-evaluation-dev:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-hybrid-evaluation-dev:latest
docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2-dev:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2-dev:latest

docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-hybrid-evaluation-dev
docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2-dev