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
    {
      imports = [
        (
          { config, lib, ... }:
          let
            emptyConfig = { };
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
          in
          {
            imports = (moduleFn emptyConfig).imports or [ ];
            options = lib.setAttrByPath modulePath optionConfig;

            config =
              let
                moduleCfg = lib.attrByPath modulePath emptyConfig config;
                enableVal = moduleCfg.enable or null;

                enabled =
                  if enableVal == false then
                    false
                  else if isAnyParentExplicitlyDisabled modulePath then
                    false
                  else if isParentExplicitlyEnabled modulePath then
                    true
                  else
                    enableVal == true;

                params = lib.filterAttrs (k: v: k != "enable" && !(lib.isAttrs v && v ? enable)) moduleCfg;

                result = moduleFn (if enabled then params else emptyConfig);
                finalCfg = lib.removeAttrs result [ "imports" ];

                moduleSettings =
                  if finalCfg ? ${builtins.head pathPrefix} then
                    { ${builtins.head pathPrefix} = finalCfg.${builtins.head pathPrefix}; }
                  else
                    { };

                otherSettings = lib.removeAttrs finalCfg (lib.singleton (builtins.head pathPrefix));
              in
              lib.mkMerge [
                moduleSettings
                (lib.mkIf enabled otherSettings)
              ];
          }
        )
      ];
    };

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
in
{
  bundle = mkOptionalBundle;
  module = mkOptionalModule;
}
