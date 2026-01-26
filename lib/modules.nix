{
  lib,
  config ? { },
}:

let
  libConfig = {
    prefix = "module";
  }
  // config;

  prefixPath = lib.splitString "." libConfig.prefix;

  mkModule =
    {
      pathPrefix,
      name,
      opts,
      moduleFn,
    }:
    (
      { config, lib, ... }:
      let
        emptyConfig = {
          enable = null;
        };
        modulePath = pathPrefix ++ lib.splitString "." name;

        optionConfig = lib.mkOption {
          default = emptyConfig;
          type = lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = "Whether to enable ${name}. Null means inherit from parent.";
              };
            }
            // (lib.mapAttrs (
              _: paramDef:
              lib.mkOption {
                type = paramDef.type;
                description = paramDef.description or "";
              }
              // lib.optionalAttrs (paramDef ? default) { default = paramDef.default; }
            ) opts);
          };
        };

        isParentExplicitlyEnabled =
          path:
          let
            atRoot = lib.length path <= lib.length pathPrefix;
            parentPath = lib.init path;
            parentCfg = lib.attrByPath parentPath null config;
            parentEnabled = parentCfg.enable or null;
          in
          !atRoot
          && (parentEnabled == true || (parentEnabled != false && isParentExplicitlyEnabled parentPath));

        isAnyParentExplicitlyDisabled =
          path:
          let
            atRoot = lib.length path <= lib.length pathPrefix;
            parentPath = lib.init path;
            parentCfg = lib.attrByPath parentPath null config;
            parentEnabled = parentCfg.enable or null;
          in
          !atRoot && (parentEnabled == false || isAnyParentExplicitlyDisabled parentPath);

        moduleConfig = lib.attrByPath modulePath emptyConfig config;

        enabled =
          if moduleConfig.enable == false then
            false
          else if isAnyParentExplicitlyDisabled modulePath then
            false
          else if isParentExplicitlyEnabled modulePath then
            true
          else
            moduleConfig.enable == true;

        output = moduleFn (if enabled then moduleConfig else emptyConfig);

        prefixKey = builtins.head pathPrefix;
        outputImports = output.imports or [ ];
        outputModules = if output ? ${prefixKey} then { ${prefixKey} = output.${prefixKey}; } else { };
        outputOtherAttrs = lib.removeAttrs output [
          prefixKey
          "imports"
        ];
      in
      {
        imports = outputImports;
        options = lib.setAttrByPath modulePath optionConfig;
        config = lib.mkIf enabled (
          lib.mkMerge [
            outputModules
            outputOtherAttrs
          ]
        );
      }
    );

  mkOptionalModule =
    name: opts: moduleFn:
    mkModule {
      inherit name opts moduleFn;
      pathPrefix = prefixPath;
    };

  mkOptionalBundle = path: modulePaths: {
    imports = [
      (mkOptionalModule path { } (cfg: { }))
      (
        { config, lib, ... }:
        {
          config = lib.mkMerge (
            map (
              modulePath:
              let
                bundlePath = prefixPath ++ lib.splitString "." path;
                fullModulePath = prefixPath ++ lib.splitString "." modulePath;
                bundleCfg = lib.attrByPath bundlePath { } config;
                bundleEnabled = bundleCfg.enable or null;
              in
              lib.setAttrByPath fullModulePath {
                enable =
                  if bundleEnabled == true then
                    lib.mkDefault true
                  else if bundleEnabled == false then
                    lib.mkOverride 75 false
                  else
                    lib.mkDefault null;
              }
            ) modulePaths
          );
        }
      )
    ];
  };

  mkWithCustomConfig =
    newConfig:
    import ./modules.nix {
      inherit lib;
      config = libConfig // newConfig;
    };
in
{
  bundle = mkOptionalBundle;
  module = mkOptionalModule;
  withConfig = mkWithCustomConfig;
}
