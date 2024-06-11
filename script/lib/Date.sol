pragma solidity ^0.8.6;

library Date {
    uint256 public constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 public constant SECONDS_PER_HOUR = 60 * 60;
    uint256 public constant SECONDS_PER_MINUTE = 60;
    uint256 public constant SECONDS_PER_MONTH = 30 * SECONDS_PER_DAY;
    uint256 public constant SECONDS_PER_YEAR = 365 * SECONDS_PER_DAY;

    function getYear(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / SECONDS_PER_YEAR;
    }

    function getMonth(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp % SECONDS_PER_YEAR) / SECONDS_PER_MONTH;
    }

    function getDay(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp % SECONDS_PER_MONTH) / SECONDS_PER_DAY;
    }

    function getHour(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp % SECONDS_PER_DAY) / SECONDS_PER_HOUR;
    }

    function getMinute(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE;
    }

    function getSecond(uint256 timestamp) internal pure returns (uint256) {
        return timestamp % SECONDS_PER_MINUTE;
    }

    function getWeekday(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / SECONDS_PER_DAY + 4) % 7;
    }

    function toTimestamp(
        uint256 year,
        uint256 month,
        uint256 day
    ) internal pure returns (uint256 timestamp) {
        uint256 _year = year - 1970;
        uint256 _month = month - 1;
        uint256 _day = day - 1;

        timestamp = _year * SECONDS_PER_YEAR;
        timestamp += _month * SECONDS_PER_MONTH;
        timestamp += _day * SECONDS_PER_DAY;
        timestamp += 4 * SECONDS_PER_DAY;
        timestamp += 1 * SECONDS_PER_HOUR;
    }
}
