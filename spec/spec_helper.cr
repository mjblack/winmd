require "spec"
require "../src/winmd"

def get_fixture(name : String)
  path = Path.new("./fixtures/" + name + ".json")
  File.read(path)
end