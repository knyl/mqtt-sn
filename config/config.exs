# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :mqttsn, ip: 'insert-ip-here',
                port: 'insert-port-here',
                dets_data_file: "insert-file-here",
                client_id: "insert_client_id_here"

config :logger, backends: [{LoggerFileBackend, :debug_log}]

config :logger, :debug_log, path: "/data/debug.log",
                            level: :debug
