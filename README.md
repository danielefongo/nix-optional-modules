# optional-modules.nix

![Nix](https://img.shields.io/badge/Nix-5277C3?style=flat-square&logo=nix&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)

A Nix library for creating optional modules with hierarchical enable/disable functionality.

## Installation

### Using Nix Flakes

Add the library to your flake inputs and extend your lib:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-optional-modules.url = "github:danielefongo/nix-optional-modules";
  };

  outputs = { nixpkgs, nix-optional-modules, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (self: super: {
            lib = super.lib // {
              # Use the default library (prefix = "module")
              opts = nix-optional-modules.lib;
            };
          })
        ];
      };
    in {
      # ...
    };
}
```

## Quick Start

### Module

```nix
{ lib, pkgs, ... }:
{
  imports = [
    (lib.opts.module "myservice"
      {
        port = {
          type = lib.types.port;
          default = 8080;
          description = "Port for my service";
        };
      }
      (cfg: {
        systemd.services.myservice = {
          description = "My custom service";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.myPackage}/bin/my-service --port ${toString cfg.port}";
          };
        };
      })
    )
  ];
  
  # Configuration
  module.myservice.enable = true;
  module.myservice.port = 9090;
}
```

### Nested module

```nix
{ lib, pkgs, ... }:
{
  imports = [
    # Parent module
    (lib.opts.module "parent" {
      value = {
        type = lib.types.int;
        default = 42;
      };
    } (cfg: { }))

    # Child module
    (lib.opts.module "parent.child" {
      name = {
        type = lib.types.str;
      };
    } (cfg: {
      output.result = "child-${cfg.name}";
    }))
  ];
  
  # Configuration
  module.parent.enable = true;
  module.parent.child.name = "test";
}
```

### Bundle

```nix
{ lib, pkgs, ... }:
{
  imports = [
    # Create a bundle that controls multiple apps
    (lib.opts.bundle "app.selfhosted" [
      "app.nextcloud"
      "app.immich"
    ])
    
    (lib.opts.module "app.nextcloud" { } (cfg: {
      home.packages = [ pkgs.nextcloud ];
    }))
    
    (lib.opts.module "app.immich" { } (cfg: {
      home.packages = [ pkgs.immich ];
    }))
  ];

  # Enable all selfhosted apps at once
  module.app.selfhosted.enable = true;
}
```

## API

- `opts.module name opts moduleFn` - Create an optional module with enable option
- `opts.bundle name modulePaths` - Create a bundle that enables/disables multiple modules
- `opts.withConfig config` - Create a new instance with modified configuration

### Module Parameters

- `name` - String name of the module (supports dot notation for nesting, e.g., "parent.child")
- `opts` - Attribute set of module options with type definitions
- `moduleFn` - Function that takes the configuration (`cfg`) and returns module settings

### Custom configuration

The `withConfig` function allows you to create a new library instance with different configuration options:

```nix
{
  lib = super.lib // {
    opts = nix-optional-modules.lib;
    cfgOpts = nix-optional-modules.lib.withConfig { prefix = "cfg"; };
  };
}
```

Now you can use both `opts` (with prefix `module`) and `cfgOpts` (with prefix `cfg`) in the same configuration:

```nix
{
  imports = [
    (lib.opts.module "myapp" { } (cfg: { ... }))
    (lib.cfgOpts.module "otherapp" { } (cfg: { ... }))
  ];

  module.myapp.enable = true;  # uses opts
  cfg.otherapp.enable = true;   # uses opts2
}
```

### Enable Options

Each module includes an `enable` option of type `nullOr bool`:

- `null` (default) - inherit from parent enable state
- `true` - explicitly enable the module
- `false` - explicitly disable the module

Parent modules control child modules:

- If parent is `false`, all children are disabled regardless of their settings (takes precedence over internal bundles)
- If parent is `true`, children inherit this unless explicitly disabled

## Testing and Contributing

### Testing

Run tests using `nix-tests`:

```bash
# Run all tests
nix-tests
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `nix-tests`
5. Submit a pull request
