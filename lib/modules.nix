{
  lib,
  config ? { },
}:

let
  libConfig = {
    prefix = "module";
  }
  // config;

  nameToPath = name: if builtins.isList name then name else lib.splitString "." name;

  nameToString = name: if builtins.isList name then lib.concatStringsSep "." name else name;

  mkDefaultEnable =
    value:
    if builtins.isAttrs value then
      if value._type or null == "override" then
        value
      else
        lib.mapAttrs (
          k: v:
          if k == "enable" then
            if builtins.isAttrs v && v._type or null == "override" then v else lib.mkDefault v
          else
            mkDefaultEnable v
        ) value
    else
      value;

  mkModule =
    {
      pathPrefix,
      name,
      opts,
      moduleFn,
    }:
    {
      imports = [
        (
          moduleArgs@{ config, lib, ... }:
          let
            prefixKey = builtins.head modulePath;
            emptyConfig = { };

            relativeModulePath = nameToPath name;
            modulePath = pathPrefix ++ relativeModulePath;

            hasParent = builtins.length relativeModulePath > 1;
            parentModulePath = if hasParent then lib.init modulePath else [ ];
            parentEnabled = lib.attrByPath (parentModulePath ++ [ "enable" ]) null config;

            moduleOptions = {
              enable = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = "Whether to enable ${nameToString name}.";
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
            moduleConfig = lib.attrByPath modulePath emptyConfig config;
            moduleEnabled = moduleConfig.enable == true;

            output = moduleFn (
              moduleArgs
              // {
                moduleConfig = if moduleEnabled then moduleConfig else emptyConfig;
              }
            );
            outputOptions = lib.setAttrByPath modulePath moduleOptions;
            outputImports = output.imports or [ ];
            outputModules =
              if output ? ${prefixKey} then { ${prefixKey} = mkDefaultEnable output.${prefixKey}; } else { };
            outputOtherAttrs = lib.removeAttrs output [
              prefixKey
              "imports"
            ];
          in
          {
            options = outputOptions;
            imports = outputImports;
            config = lib.mkMerge [
              (lib.mkIf moduleEnabled (
                lib.mkMerge [
                  outputModules
                  outputOtherAttrs
                ]
              ))
              (lib.mkIf (hasParent && parentEnabled == false) (
                lib.setAttrByPath modulePath {
                  enable = lib.mkOverride 75 false;
                }
              ))
              (lib.mkIf (hasParent && parentEnabled == true) (
                lib.setAttrByPath modulePath {
                  enable = lib.mkDefault true;
                }
              ))
            ];
          }
        )
      ];
    };

  mkOptionalModule =
    name: opts: moduleFn:
    mkModule {
      inherit name opts moduleFn;
      pathPrefix = nameToPath libConfig.prefix;
    };

  mkOptionalBundle = path: modulePaths: {
    imports = [
      (mkOptionalModule path { } (_: { }))
      (
        { config, lib, ... }:
        {
          config = lib.mkMerge (
            map (
              modulePath:
              let
                prefixPath = nameToPath libConfig.prefix;
                bundlePath = prefixPath ++ (nameToPath path);
                fullModulePath = prefixPath ++ (nameToPath modulePath);
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
