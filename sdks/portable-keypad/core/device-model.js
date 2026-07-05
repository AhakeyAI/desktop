const componentTypes = {
  button: ["press", "hold", "release", "double_press"],
  encoder: ["rotate_left", "rotate_right", "press", "press_rotate_left", "press_rotate_right"],
  toggle: ["position_1", "position_2", "position_3"],
  joystick: ["up", "down", "left", "right", "press", "axis_x", "axis_y"],
};

function createDeviceModel({ adapter, device, layout, layers }) {
  return {
    sdkVersion: "0.1.0",
    adapter,
    device,
    layout,
    layers,
  };
}

function createEmptyBindings(layout, layerCount = 10) {
  const actions = layout.components.flatMap((component) => component.actions);
  const layers = {};
  for (let layer = 0; layer < layerCount; layer += 1) {
    layers[layer] = {};
    for (const action of actions) {
      layers[layer][action.id] = {
        type: "unassigned",
        value: null,
      };
    }
  }
  return layers;
}

module.exports = {
  componentTypes,
  createDeviceModel,
  createEmptyBindings,
};
