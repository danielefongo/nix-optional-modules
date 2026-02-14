{
  pkgs ? import <nixpkgs> { },
  nix-tests,
}:

let
  lib = pkgs.lib;
  opts = import ./modules.nix { inherit lib; };
  tests = nix-tests;

  simulateConfig =
    config:
    lib.evalModules {
      modules = [
        {
          options.output = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          options.home = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
        }
        config
      ];
    };
in
tests.runTests {
  "raw module is valid" = t: rec {
    cfg = opts.module "mod" { } (_: { });

    "it is a set" = t.isTrue (lib.isAttrs cfg);
    "has imports" = t.hasAttr "imports" cfg;
  };

  "module creates a config" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod" {
          value = {
            type = lib.types.int;
            default = 42;
          };
          value2 = {
            type = lib.types.str;
          };
        } (_: { }))
      ];

      module.mod.value2 = "custom value";
    };

    "has module option" = t.hasAttr "mod" cfg.options.module;
    "config is set" = t.isEq cfg.config.module.mod {
      enable = null;
      value = 42;
      value2 = "custom value";
    };
  };

  "nested module creates a config" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent.child" {
          value = {
            type = lib.types.int;
            default = 42;
          };
        } (_: { }))
      ];
    };

    "has parent option" = t.hasAttr "parent" cfg.options.module;
    "has child option" = t.hasAttr "child" cfg.options.module.parent;
    "config is set" = t.isEq cfg.config.module.parent.child {
      enable = null;
      value = 42;
    };
  };

  "enabled module sets output" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod"
          {
            count = {
              type = lib.types.int;
              default = 10;
            };
            name = {
              type = lib.types.str;
            };
          }
          (
            { moduleConfig, ... }:
            {
              output.value = "${moduleConfig.name}-${toString moduleConfig.count}";
            }
          )
        )
      ];

      module.mod = {
        enable = true;
        name = "foo";
      };
    };

    "is enabled" = t.isEq cfg.config.module.mod.enable true;
    "output is set" = t.isEq cfg.config.output {
      value = "foo-10";
    };
  };

  "disabled module does not set output" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod" { } (_: {
          output.shouldNotExist = "This should not be set if module is disabled";
        }))
      ];
      module.mod.enable = false;
    };

    "is not enabled" = t.isEq cfg.config.module.mod.enable false;
    "output is not set" = t.isEq cfg.config.output { };
  };

  "disabled module by default" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod" { } (_: {
          output.shouldNotExist = "This should not be set if module is disabled";
        }))
      ];
    };

    "enable is not defined" = t.isNull cfg.config.module.mod.enable;
    "output is not set" = t.isEq cfg.config.output { };
  };

  "nested module enabled by parent" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent" { } (_: { }))
        (opts.module "parent.child" { } (_: {
          output.val = 42;
        }))
      ];

      module.parent.enable = true;
    };

    "child inherits enable from parent" = t.isTrue cfg.config.module.parent.child.enable;
    "output is set" = t.isEq cfg.config.output {
      val = 42;
    };
  };

  "nested module disabled by parent" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent" { } (_: { }))
        (opts.module "parent.child" { } (_: {
          output.shouldNotExist = "This should not be set if parent is disabled";
        }))
      ];

      module.parent.enable = false;
      module.parent.child.enable = true;
    };

    "child is disabled by parent" = t.isEq cfg.config.module.parent.child.enable false;
    "output is not set" = t.isEq cfg.config.output { };
  };

  "parent module can disable child module" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod"
          {
            disable_child = {
              type = lib.types.bool;
              default = false;
            };
          }
          (
            { moduleConfig, ... }:
            {
              module.mod.child.enable = lib.mkForce (!moduleConfig.disable_child);
            }
          )
        )
        (opts.module "mod.child" { } (_: {
          output.xxx = true;
        }))
      ];

      module.mod = {
        enable = true;
        disable_child = true;
      };
    };

    "output is not set" = t.isEq cfg.config.output { };
  };

  "parent module can force disable child with mkForce" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent"
          {
            disable_child = {
              type = lib.types.bool;
              default = false;
            };
          }
          (
            { moduleConfig, ... }:
            {
              module.parent.child.enable = lib.mkForce (!moduleConfig.disable_child);
            }
          )
        )
        (opts.module "parent.child" { } (_: {
          output.child = true;
        }))
      ];

      module.parent = {
        enable = true;
        disable_child = true;
      };
      module.parent.child.enable = true;
    };

    "child is force disabled" = t.isEq cfg.config.module.parent.child.enable false;
    "output is not set" = t.isEq cfg.config.output { };
  };

  "child module can be forced enabled with mkForce" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent" { } (_: { }))
        (opts.module "parent.child" { } (_: {
          output.child = true;
        }))
      ];

      module.parent.enable = false;
      module.parent.child.enable = lib.mkForce true;
    };

    "parent is disabled" = t.isEq cfg.config.module.parent.enable false;
    "child is enabled with mkForce" = t.isEq cfg.config.module.parent.child.enable true;
    "output is set" = t.isEq cfg.config.output { child = true; };
  };

  "module enables another module" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod1" { } (_: {
          module.mod2.enable = true;
          output.mod1 = true;
        }))
        (opts.module "mod2" { } (_: {
          output.mod2 = true;
        }))
      ];

      module.mod1.enable = true;
    };

    "mod1 is enabled" = t.isEq cfg.config.module.mod1.enable true;
    "mod2 is enabled" = t.isEq cfg.config.module.mod2.enable true;
    "both outputs are set" = t.isEq cfg.config.output {
      mod1 = true;
      mod2 = true;
    };
  };

  "disabled module does not enable another module" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod1" { } (_: {
          module.mod2.enable = true;
          output.mod1 = true;
        }))
        (opts.module "mod2" { } (_: {
          output.mod2 = true;
        }))
      ];
    };

    "mod1 enable is null" = t.isNull cfg.config.module.mod1.enable;
    "output is not set" = t.isEq cfg.config.output { };
  };

  "nested module enables another module" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "mod" { } (_: { }))
        (opts.module "mod.child1" { } (_: {
          module.mod.child2.enable = true;
          output.child1 = true;
        }))
        (opts.module "mod.child2" { } (_: {
          output.child2 = true;
        }))
      ];

      module.mod.child1.enable = true;
    };

    "child1 is enabled" = t.isTrue cfg.config.module.mod.child1.enable;
    "child2 is enabled by child1" = t.isTrue cfg.config.module.mod.child2.enable;
    "both outputs are set" = t.isEq cfg.config.output {
      child1 = true;
      child2 = true;
    };
  };

  "module with nested imports" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent" { } (_: {
          imports = [
            (opts.module "parent.child" { } (_: {
              output.child = "from child";
            }))
          ];
          output.parent = "from parent";
        }))
      ];

      module.parent.enable = true;
    };

    "parent is enabled" = t.isEq cfg.config.module.parent.enable true;
    "child inherits enable from parent" = t.isTrue cfg.config.module.parent.child.enable;
    "both outputs are set" = t.isEq cfg.config.output {
      parent = "from parent";
      child = "from child";
    };
  };

  "raw bundle is valid" = t: rec {
    cfg = opts.bundle "bundle" [ "mod" ];

    "it is a set" = t.isTrue (lib.isAttrs cfg);
    "has imports" = t.hasAttr "imports" cfg;
  };

  "bundle enables all children" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.bundle "bundle" [
          "mod1"
          "mod2"
          "mod3"
        ])
        (opts.module "mod1" { } (_: {
          output.mod1 = true;
        }))
        (opts.module "mod2" { } (_: {
          output.mod2 = true;
        }))
        (opts.module "mod3" { } (_: {
          output.mod3 = true;
        }))
      ];

      module.bundle.enable = true;
    };

    "bundle is enabled" = t.isEq cfg.config.module.bundle.enable true;
    "mod1 is enabled" = t.isEq cfg.config.module.mod1.enable true;
    "mod2 is enabled" = t.isEq cfg.config.module.mod2.enable true;
    "mod3 is enabled" = t.isEq cfg.config.module.mod3.enable true;
    "all outputs are set" = t.isEq cfg.config.output {
      mod1 = true;
      mod2 = true;
      mod3 = true;
    };
  };

  "bundle disabled overrides enabled children" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.bundle "bundle" [
          "mod1"
          "mod2"
        ])
        (opts.module "mod1" { } (_: {
          output.mod1 = true;
        }))
        (opts.module "mod2" { } (_: {
          output.mod2 = true;
        }))
      ];

      module.bundle.enable = false;
      module.mod1.enable = true;
      module.mod2.enable = true;
    };

    "bundle is disabled" = t.isEq cfg.config.module.bundle.enable false;
    "mod1 is disabled" = t.isEq cfg.config.module.mod1.enable false;
    "mod2 is disabled" = t.isEq cfg.config.module.mod2.enable false;
    "no output is set" = t.isEq cfg.config.output { };
  };

  "multiple bundles sharing modules" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.bundle "bundle1" [
          "mod1"
          "mod2"
        ])
        (opts.bundle "bundle2" [
          "mod2"
        ])
        (opts.bundle "bundle3" [
          "mod1"
        ])
        (opts.module "mod1" { } (_: {
          output.mod1 = true;
        }))
        (opts.module "mod2" { } (_: {
          output.mod2 = true;
        }))
      ];

      module.bundle1.enable = true;
      module.bundle2.enable = true;
      module.bundle3.enable = false;
    };

    "bundle1 is enabled" = t.isEq cfg.config.module.bundle1.enable true;
    "mod1 is disabled" = t.isEq cfg.config.module.mod1.enable false;
    "mod2 is enabled" = t.isEq cfg.config.module.mod2.enable true;
    "outputs is set" = t.isEq cfg.config.output {
      mod2 = true;
    };
  };

  "bundle with parent" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent" { } (_: { }))
        (opts.bundle "parent.bundle" [
          "parent.mod1"
          "parent.mod2"
        ])
        (opts.module "parent.mod1" { } (_: {
          output.mod1 = true;
        }))
        (opts.module "parent.mod2" { } (_: {
          output.mod2 = true;
        }))
      ];

      module.parent.enable = true;
      module.parent.bundle.enable = true;
    };

    "parent is enabled" = t.isEq cfg.config.module.parent.enable true;
    "bundle is enabled" = t.isEq cfg.config.module.parent.bundle.enable true;
    "outputs are set" = t.isEq cfg.config.output {
      mod1 = true;
      mod2 = true;
    };
  };

  "parent disabled overrides bundle enabled" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "parent" { } (_: { }))
        (opts.bundle "parent.bundle" [
          "parent.mod1"
          "parent.mod2"
        ])
        (opts.module "parent.mod1" { } (_: {
          output.mod1 = true;
        }))
        (opts.module "parent.mod2" { } (_: {
          output.mod2 = true;
        }))
      ];

      module.parent.enable = false;
      module.parent.bundle.enable = true;
    };

    "parent is disabled" = t.isEq cfg.config.module.parent.enable false;
    "bundle is disabled by parent" = t.isEq cfg.config.module.parent.bundle.enable false;
    "no output is set" = t.isEq cfg.config.output { };
  };

  "custom prefix" = t: rec {
    optsCustom = import ./modules.nix {
      inherit lib;
      config = {
        prefix = "prefix";
      };
    };

    cfg = simulateConfig {
      imports = [
        (optsCustom.module "path.to.mod" {
          value = { };
        } (_: { }))
      ];

      prefix.path.to.mod.enable = true;
    };

    "module is enabled" = t.isTrue cfg.config.prefix.path.to.mod.enable;
  };

  "multi-part prefix" = t: rec {
    optsCustom = import ./modules.nix {
      inherit lib;
      config = {
        prefix = "my.long.prefix";
      };
    };

    cfg = simulateConfig {
      imports = [
        (optsCustom.module "path.to.mod" { } (_: {
          output.result = true;
        }))
      ];

      my.long.prefix.path.to.mod.enable = true;
    };

    "module is enabled" = t.isEq cfg.config.my.long.prefix.path.to.mod.enable true;
  };

  "custom config" = t: rec {
    opts1 = import ./modules.nix {
      inherit lib;
      config = {
        prefix = "cfg";
      };
    };
    opts2 = opts1.withConfig { prefix = "opt"; };

    cfg = simulateConfig {
      imports = [
        (opts1.module "mod1" { } (cfg: {
          output.mod1 = true;
        }))
        (opts2.module "mod2" { } (cfg: {
          output.mod2 = true;
        }))
      ];

      cfg.mod1.enable = true;
      opt.mod2.enable = true;
    };

    "mod1 is enabled via cfg prefix" = t.isTrue cfg.config.cfg.mod1.enable;
    "mod2 is enabled via opt prefix" = t.isTrue cfg.config.opt.mod2.enable;
    "both outputs are set" = t.isEq cfg.config.output {
      mod1 = true;
      mod2 = true;
    };
  };

  "module can access global configuration" = t: rec {
    cfg = simulateConfig {
      imports = [
        (opts.module "modA" { } (_: {
          output.modA = "outputA";
        }))
        (opts.module "modB" { } (
          {
            config,
            ...
          }:
          {
            module.modC.enable = config.module.modA.enable or false;
            output.modB = "outputB";
          }
        ))
        (opts.module "modC" { } (_: {
          output.modC = "outputC";
        }))
      ];

      module.modA.enable = true;
      module.modB.enable = true;
    };

    "modA is enabled" = t.isTrue cfg.config.module.modA.enable;
    "modB is enabled" = t.isTrue cfg.config.module.modB.enable;
    "modC is enabled by modB" = t.isTrue cfg.config.module.modC.enable;
    "all outputs are set" = t.isEq cfg.config.output {
      modA = "outputA";
      modB = "outputB";
      modC = "outputC";
    };
  };
}
