mod angles;
mod elements;
mod propagation;

const G: u128 = 1231191040; // 6.67430e-11 m^3 kg^-1 s^-2 (f128)
const G_1000: u128 = 1231191039712; // 6.67430e-8 m^3 kg^-1 s^-2 (f128)
const MU: u128 = 2097177677183526006463255493728; // 1.7033730830877267e30 * 6.67430e-20 km^3 kg^-1 s^-2 (f128)