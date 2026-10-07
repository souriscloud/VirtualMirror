#!/usr/bin/env swift
import Foundation
let script = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
let directory = script.deletingLastPathComponent()
let kit = directory.appendingPathComponent("installer")
let config = try JSONSerialization.jsonObject(with:Data(contentsOf:kit.appendingPathComponent("config.json"))) as! [String:String]
let root = directory.deletingLastPathComponent()
let output = CommandLine.arguments.dropFirst().first(where:{ !$0.hasPrefix("--") })
  ?? root.appendingPathComponent(config["legacy_background"]!).path
try FileManager.default.createDirectory(at:URL(fileURLWithPath:output).deletingLastPathComponent(),withIntermediateDirectories:true)
for scale in 1...2 {
 let base = URL(fileURLWithPath:output)
 let path = scale == 1 ? output : base.deletingPathExtension().path + "@\(scale)x." + base.pathExtension
 var arguments = ["swift",kit.appendingPathComponent("render.swift").path,
   "--name",config["name"]!,"--subtitle",config["subtitle"]!,
   "--output",path,"--scale",String(scale)]
 if CommandLine.arguments.contains("--preview") {
  arguments += ["--icon",root.appendingPathComponent(config["preview_icon"]!).path]
 }
 let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
 process.arguments = arguments
 try process.run(); process.waitUntilExit()
 guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
}
