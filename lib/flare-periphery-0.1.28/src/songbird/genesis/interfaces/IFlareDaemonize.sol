// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;


/// Any contracts that want to recieve a trigger from Flare daemon should 
///     implement IFlareDaemonize
interface IFlareDaemonize {

    /// Implement this function for recieving a trigger from FlareDaemon.
    function daemonize() external returns (bool);
    
    /// This function will be called after an error is caught in daemonize().
    /// It will switch the contract to a simpler fallback mode, which hopefully works when full mode doesn't.
    /// Not every contract needs to support fallback mode (FtsoManager does), so this method may be empty.
    /// Switching back to normal mode is left to the contract (typically a governed method call).
    /// This function may be called due to low-gas error, so it shouldn't use more than ~30.000 gas.
    /// @return true if switched to fallback mode, false if already in fallback mode or if falback not supported
    function switchToFallbackMode() external returns (bool);
}
