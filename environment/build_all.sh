SPIKEINTERFACE_VERSION=$(grep '^spikeinterface==' requirements.txt | cut -d'=' -f3)

# docker build -t ghcr.io/allenneuraldynamics/aind-ephys-hybrid-generation-dev:si-$SPIKEINTERFACE_VERSION -f Dockerfile_generation .
docker build -t ghcr.io/allenneuraldynamics/aind-ephys-hybrid-evaluation-dev:si-$SPIKEINTERFACE_VERSION -f Dockerfile_evaluation .
# docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2-dev:si-$SPIKEINTERFACE_VERSION -f Dockerfile_spykingcircus2 .