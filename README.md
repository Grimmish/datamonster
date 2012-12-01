datamonster
===========

A loose collection of scripts intended to form a complete auto-racing telemetry system - collection, analysis, visualization.

Organization
------------
Datamonster is composed of two primary roles: The collector (client) role consists of the components running in-car that collect data from sensors, OBD-II, and other sources and uploads it to the analysis server. The analyzer (server) role compiles and stores data transmitted from the collector and presents it in a useful way via a web interface.