"""
This script creates a 2-minute synthetic NWB file with 3 electrical series for testing the pipeline.

Requirements:
- spikeinterface
- pynwb
- neuroconv
"""

import spikeinterface as si
from pathlib import Path

from pynwb import NWBHDF5IO
from pynwb.testing.mock.file import mock_NWBFile, mock_Subject
from neuroconv.tools.spikeinterface import add_recording_to_nwbfile

this_folder = Path(__file__).parent

num_files = 1
num_recordings = 3
duration = 120


num_channels = 64
num_units = 20
output_folder = this_folder / "nwb"
output_folder.mkdir(exist_ok=True)

nwbfile = mock_NWBFile()
nwbfile.subject = mock_Subject()

for n in range(num_files):
    for i in range(num_recordings):
        recording, _ = si.generate_ground_truth_recording(
            num_channels=num_channels,
            num_units=num_units,
            durations=[duration],
        )
        probe_device_name = f"Probe{i}"
        electrode_metadata = dict(
            Ecephys=dict(
                Device=[dict(name=probe_device_name)],
                ElectrodeGroup=[
                    dict(
                        name=probe_device_name,
                        description=f"Recorded electrodes from probe {probe_device_name}",
                        location="unknown",
                        device=probe_device_name,
                    )
                ],
            )
        )
        # Add channel properties (group_name property to associate electrodes with group)
        recording.set_channel_groups([probe_device_name] * recording.get_num_channels())
        electrical_series_name = f"ElectricalSeries{probe_device_name}"
        electrical_series_metadata = {
            electrical_series_name: dict(
                name=f"ElectricalSeries{probe_device_name}",
                description=f"Voltage traces from {probe_device_name}",
            )
        }
        electrode_metadata["Ecephys"].update(electrical_series_metadata)
        add_electrical_series_kwargs = dict(
            es_key=f"ElectricalSeries{probe_device_name}", write_as="raw"
        )
        add_recording_to_nwbfile(recording, nwbfile=nwbfile, metadata=electrode_metadata, **add_electrical_series_kwargs)

    with NWBHDF5IO(output_folder / f"session{n+1}.nwb", mode="w") as io:
        io.write(nwbfile)